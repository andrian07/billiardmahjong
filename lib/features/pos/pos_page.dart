import 'package:flutter/material.dart';

import '../../core/constants/app_sizes.dart';
import '../../core/navigation/app_navigation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/utils/formatters.dart';
import '../../models/cart_addon.dart';
import '../../models/cart_item.dart';
import '../../models/keep_transaction.dart';
import '../../models/product.dart';
import '../../models/product_category.dart';
import '../../services/receipt_printer_service.dart';
import '../../services/session_storage.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_layout.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/ticket_preview.dart';
import '../product/data/product_repository.dart';
import 'data/cafe_invoice_repository.dart';
import 'data/cafe_repository.dart';
import 'widgets/cafe_payment_dialog.dart';
import 'widgets/cart_item_addon_dialog.dart';
import 'widgets/cart_item_note_dialog.dart';
import 'widgets/keep_transaction_list_dialog.dart';
import 'widgets/keep_transaction_name_dialog.dart';

/// POS (point-of-sale) screen for selling products at the counter.
///
/// Checkout submits the cart to Cafe/save_transaction_cafe via
/// [CafePaymentDialog]. The product catalog itself is real (same data as
/// the Produk page).
class PosPage extends StatefulWidget {
  const PosPage({super.key});

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  final _repository = ProductRepository();
  final _cafeRepository = CafeRepository();
  final _cafeInvoiceRepository = CafeInvoiceRepository();
  final _receiptPrinter = ReceiptPrinterService();
  final _sessionStorage = SessionStorage();
  final _searchController = TextEditingController();

  List<Product> _products = [];
  List<ProductCategory> _categories = [];
  bool _loading = true;
  String? _error;

  String _search = "";
  int? _selectedCategoryId;
  bool _keepingTransaction = false;

  final Map<int, CartItem> _cart = {};

  /// Set once the cart is tied to a held transaction (either just parked, or
  /// loaded back via "Pesanan Tertunda") so the next SIMPAN adds items onto
  /// that same record instead of creating a duplicate. Cleared whenever the
  /// cart is cleared/checked out.
  int? _activeKeepTransactionId;
  String? _activeKeepTransactionName;

  /// Snapshot (qty/note/addons) of each item as it was last persisted to the
  /// held transaction, so [_pendingKeepItems] can tell whether an item needs
  /// resending because ANYTHING changed — not just its quantity going up.
  Map<int, CartItem> _keepBaseline = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final products = await _repository.getProducts();
      final categories = await _repository.getCategoryOptions();
      if (!mounted) return;
      setState(() {
        _products = products;
        _categories = categories;
        _loading = false;
      });
    } on ProductRepositoryException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  List<Product> get _filteredProducts {
    final query = _search.trim().toLowerCase();

    return _products.where((p) {
      if (_selectedCategoryId != null && p.categoryId != _selectedCategoryId) {
        return false;
      }
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          p.code.toLowerCase().contains(query);
    }).toList();
  }

  List<CartItem> get _cartItems => _cart.values.toList();

  int get _cartCount =>
      _cart.values.fold(0, (sum, item) => sum + item.quantity);

  int get _subtotal =>
      _cart.values.fold(0, (sum, item) => sum + item.lineTotal);

  void _addToCart(Product product) {
    setState(() {
      final existing = _cart[product.id];
      _cart[product.id] = CartItem(
        product: product,
        quantity: (existing?.quantity ?? 0) + 1,
      );
    });
  }

  void _incrementQty(int productId) {
    final item = _cart[productId];
    if (item == null) return;
    setState(
      () => _cart[productId] = item.copyWith(quantity: item.quantity + 1),
    );
  }

  void _decrementQty(int productId) {
    final item = _cart[productId];
    if (item == null) return;

    if (item.quantity <= 1) {
      setState(() => _cart.remove(productId));
    } else {
      setState(
        () => _cart[productId] = item.copyWith(quantity: item.quantity - 1),
      );
    }
  }

  void _removeFromCart(int productId) {
    setState(() => _cart.remove(productId));
  }

  Future<void> _editItemNote(CartItem item) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => CartItemNoteDialog(item: item),
    );
    if (result == null) return;

    setState(() => _cart[item.product.id] = item.withNote(result));
  }

  Future<void> _editItemAddons(CartItem item) async {
    final result = await showDialog<List<CartAddon>>(
      context: context,
      builder: (_) => CartItemAddonDialog(item: item, products: _products),
    );
    if (result == null) return;

    setState(() => _cart[item.product.id] = item.withAddons(result));
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
      _activeKeepTransactionId = null;
      _activeKeepTransactionName = null;
      _keepBaseline = {};
    });
  }

  /// Items still needing to be persisted for the active held transaction.
  /// Quantity is sent as only the extra amount added on top of what the
  /// server already has (a repeat keep-transaction call *adds* to existing
  /// quantity rather than replacing it) — but an item is still included with
  /// quantity 0 when only its note or additional items changed, since those
  /// DO fully replace what the server has and would otherwise silently never
  /// reach it if the base quantity didn't also change.
  List<CartItem> get _pendingKeepItems {
    if (_activeKeepTransactionId == null) return _cartItems;

    final result = <CartItem>[];
    for (final item in _cartItems) {
      final baseline = _keepBaseline[item.product.id];
      final delta = item.quantity - (baseline?.quantity ?? 0);
      final noteChanged = item.note != baseline?.note;
      final addonsChanged = !_addonsMatch(
        item.addons,
        baseline?.addons ?? const [],
      );

      if (delta > 0 || noteChanged || addonsChanged) {
        result.add(item.copyWith(quantity: delta > 0 ? delta : 0));
      }
    }
    return result;
  }

  bool _addonsMatch(List<CartAddon> a, List<CartAddon> b) {
    if (a.length != b.length) return false;
    final aByProduct = {
      for (final addon in a) addon.product.id: addon.quantity,
    };
    for (final addon in b) {
      if (aByProduct[addon.product.id] != addon.quantity) return false;
    }
    return true;
  }

  Future<void> _checkout() async {
    final items = _cartItems;
    final subtotal = _subtotal;
    final keepTransactionId = _activeKeepTransactionId;

    final result = await showDialog<CafePaymentResult>(
      context: context,
      builder: (_) => CafePaymentDialog(
        items: items,
        subtotal: subtotal,
        initialCustomerName: _activeKeepTransactionName,
      ),
    );
    if (result == null) return;
    if (!mounted) return;

    setState(() {
      _cart.clear();
      _activeKeepTransactionId = null;
      _activeKeepTransactionName = null;
      _keepBaseline = {};
    });
    AppToast.success(
      context,
      "Transaksi cafe berhasil (#${result.transactionCafeId})",
    );
    await _refreshProductStock();

    // The sale itself already succeeded — if this cart came from a parked
    // "Pesanan Tertunda" order, drop that held record too, otherwise it
    // keeps showing up as still-pending even though it's been paid.
    // Best-effort: a failure here doesn't affect the completed sale, it
    // would just leave a stale entry staff can clear manually.
    if (keepTransactionId != null) {
      try {
        await _cafeRepository.deleteKeepTransaction(keepTransactionId);
      } catch (_) {}
    }

    try {
      final session = await _sessionStorage.getSession();
      final cashierName = session?['username']?.toString() ?? "Kasir";
      final receipt = await _cafeInvoiceRepository.generateInvoice(
        items: items,
        subtotal: subtotal,
        payment: result,
        cashierName: cashierName,
      );

      // Kitchen slip first, then the customer-facing payment receipt —
      // printed as two independent attempts so one failing doesn't stop
      // the other from being tried.
      if (result.printKitchenTicket) {
        try {
          await _receiptPrinter.printKitchenOrder(
            keepCode: receipt.invoiceNumber,
            customerName: result.customerName,
            items: items,
          );
        } catch (e) {
          if (!mounted) return;
          AppToast.error(context, "Gagal mencetak struk dapur: $e");
        }
      }

      if (!mounted) return;
      try {
        await _receiptPrinter.printCafeReceipt(receipt);
      } on ReceiptPrinterNotFoundException {
        if (!mounted) return;
        await TicketPreviewDialog.show(
          context,
          title: "PREVIEW STRUK - printer tidak ditemukan",
          children: TicketPreviewContent.cafe(receipt),
        );
        return;
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error(context, "Gagal mencetak struk: $e");
    }
  }

  /// Re-fetches the product list after a sale so displayed stock reflects
  /// what the server just deducted — without the full-screen loading state
  /// [_load] uses, since the grid is already visible and shouldn't flash.
  Future<void> _refreshProductStock() async {
    try {
      final products = await _repository.getProducts();
      if (!mounted) return;
      setState(() => _products = products);
    } on ProductRepositoryException {
      // Stale stock until the next full reload; the sale itself already
      // succeeded, so this silently no-ops rather than surfacing an error.
    }
  }

  Future<void> _keepTransaction() async {
    if (_cart.isEmpty || _keepingTransaction) return;

    final itemsToSend = _pendingKeepItems;
    if (itemsToSend.isEmpty) {
      // Loaded order re-saved with no new items added — nothing to persist.
      _clearCart();
      return;
    }

    // The name is only ever stored on a brand-new keep transaction — the
    // server ignores it once one already exists — so only ask for it then.
    // Picking (or typing) a name that matches an already-held transaction
    // merges the cart into that one instead of parking a duplicate.
    String? name;
    var targetKeepTransactionId = _activeKeepTransactionId;
    if (_activeKeepTransactionId == null) {
      final entered = await showDialog<KeepTransactionNameResult>(
        context: context,
        builder: (_) => const KeepTransactionNameDialog(),
      );
      if (entered == null) return;
      name = entered.name;
      targetKeepTransactionId = entered.matchedKeepTransactionId;
    }

    setState(() => _keepingTransaction = true);

    try {
      final session = await _sessionStorage.getSession();
      final createdBy = session?['username']?.toString() ?? "";

      final result = await _cafeRepository.keepTransaction(
        keepTransactionId: targetKeepTransactionId,
        name: name,
        createdBy: createdBy,
        items: itemsToSend,
      );

      final merged =
          _activeKeepTransactionId == null && targetKeepTransactionId != null;

      if (!mounted) return;
      setState(() {
        _cart.clear();
        _activeKeepTransactionId = null;
        _keepBaseline = {};
        _keepingTransaction = false;
      });
      AppToast.success(
        context,
        merged
            ? "Item ditambahkan ke pesanan \"$name\" (#${result.id})"
            : "Pesanan ditahan sementara (#${result.id})",
      );

      try {
        await _receiptPrinter.printKitchenOrder(
          keepCode: result.invoiceNumber,
          customerName: result.name,
          items: itemsToSend,
        );
      } catch (e) {
        if (!mounted) return;
        AppToast.error(context, "Gagal mencetak struk dapur: $e");
      }
    } on CafeRepositoryException catch (e) {
      if (!mounted) return;
      setState(() => _keepingTransaction = false);
      AppToast.error(context, e.message);
    }
  }

  Future<void> _openKeepTransactions() async {
    final detail = await showDialog<KeepTransactionDetail>(
      context: context,
      builder: (_) => const KeepTransactionListDialog(),
    );
    if (detail == null) return;
    if (!mounted) return;

    if (_cart.isNotEmpty) {
      final confirmed = await _confirm(
        title: "Ganti Keranjang?",
        message:
            "Keranjang saat ini akan diganti dengan pesanan ${detail.invoiceNumber} yang ditahan.",
        confirmLabel: "LANJUTKAN",
      );
      if (!confirmed) return;
    }

    setState(() {
      _cart.clear();
      _keepBaseline = {};
      for (final item in detail.items) {
        final product = _products.firstWhere(
          (p) => p.id == item.productId,
          orElse: () => Product(
            id: item.productId,
            code: "",
            name: item.productName,
            price: item.productPrice,
            cogs: 0,
            stock: 0,
            reduceStock: false,
            image: "",
            imageUrl: "",
          ),
        );
        _cart[item.productId] = CartItem(
          product: product,
          quantity: item.quantity,
          note: item.note,
          addons: [
            for (final addon in item.addons)
              CartAddon(
                product: _products.firstWhere(
                  (p) => p.id == addon.productId,
                  orElse: () => Product(
                    id: addon.productId,
                    code: "",
                    name: addon.productName,
                    price: addon.productPrice,
                    cogs: 0,
                    stock: 0,
                    reduceStock: false,
                    image: "",
                    imageUrl: "",
                  ),
                ),
                quantity: addon.quantity,
              ),
          ],
        );
        _keepBaseline[item.productId] = _cart[item.productId]!;
      }
      _activeKeepTransactionId = detail.id;
      _activeKeepTransactionName = detail.name;
    });

    if (!mounted) return;
    AppToast.success(
      context,
      "Pesanan ${detail.invoiceNumber} dimuat ke keranjang",
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusLarge),
        ),
        title: Text(title, style: AppText.title),
        content: Text(message, style: AppText.bodySecondary),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("BATAL"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: "POS",
      subtitle: "Kasir penjualan produk",
      showSearch: false,
      activeMenuKey: "pos",
      onMenuSelect: (key) => navigateToMenu(context, key),
      onRefresh: _load,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: _buildProductPanel()),
          const SizedBox(width: 16),
          SizedBox(width: 360, child: _buildCartPanel()),
        ],
      ),
    );
  }

  Widget _buildProductPanel() {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _search = value),
            style: AppText.body,
            decoration: const InputDecoration(
              isDense: true,
              hintText: "Cari nama atau kode produk...",
              prefixIcon: Icon(Icons.search, size: 20),
              contentPadding: EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          _buildCategoryChips(),
          const SizedBox(height: 12),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 12),
          Expanded(child: _buildProductGrid()),
        ],
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _categoryChip(
            label: "Semua",
            selected: _selectedCategoryId == null,
            onTap: () {
              setState(() => _selectedCategoryId = null);
            },
          ),
          const SizedBox(width: 8),
          for (final category in _categories) ...[
            _categoryChip(
              label: category.name,
              selected: _selectedCategoryId == category.id,
              onTap: () => setState(() => _selectedCategoryId = category.id),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  Widget _categoryChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildMessageState(
        icon: Icons.cloud_off_rounded,
        iconColor: AppColors.danger,
        message: _error!,
        action: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text("Coba Lagi"),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            ),
          ),
        ),
      );
    }

    final products = _filteredProducts;
    if (products.isEmpty) {
      return _buildMessageState(
        icon: Icons.inventory_2_outlined,
        iconColor: AppColors.textHint,
        message: "Tidak ada produk ditemukan",
      );
    }

    return GridView.builder(
      itemCount: products.length,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 170,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: .78,
      ),
      itemBuilder: (context, index) =>
          _ProductCard(product: products[index], onTap: _addToCart),
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required Color iconColor,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: iconColor),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.bodySecondary,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    );
  }

  Widget _buildCartPanel() {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
                  ),
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Keranjang",
                        style: AppText.title.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text("$_cartCount item", style: AppText.caption),
                    ],
                  ),
                ),
                Tooltip(
                  message: "Pesanan Tertunda",
                  child: InkWell(
                    onTap: _openKeepTransactions,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.pending_actions_rounded,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
                if (_cart.isNotEmpty)
                  InkWell(
                    onTap: _clearCart,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        "KOSONGKAN",
                        style: AppText.caption.copyWith(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Expanded(
            child: _cart.isEmpty
                ? _buildMessageState(
                    icon: Icons.shopping_cart_outlined,
                    iconColor: AppColors.textHint,
                    message:
                        "Keranjang masih kosong.\nPilih produk untuk mulai.",
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _cartItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = _cartItems[index];
                      return _CartRow(
                        item: item,
                        onIncrement: () => _incrementQty(item.product.id),
                        onDecrement: () => _decrementQty(item.product.id),
                        onRemove: () => _removeFromCart(item.product.id),
                        onEditNote: () => _editItemNote(item),
                        onEditAddons: () => _editItemAddons(item),
                      );
                    },
                  ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Total",
                      style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      formatCurrency(_subtotal),
                      style: AppText.title.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _cart.isEmpty || _keepingTransaction
                            ? null
                            : _keepTransaction,
                        icon: _keepingTransaction
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.pause_circle_outline_rounded,
                                size: 20,
                              ),
                        label: const Text("SIMPAN"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.textHint,
                          minimumSize: const Size(0, 48),
                          elevation: 0,
                          textStyle: AppText.button,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppSizes.radiusMedium,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _cart.isEmpty ? null : _checkout,
                        icon: const Icon(Icons.point_of_sale_rounded, size: 20),
                        label: const Text("BAYAR"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.textHint,
                          minimumSize: const Size(0, 48),
                          elevation: 0,
                          textStyle: AppText.button,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppSizes.radiusMedium,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final ValueChanged<Product> onTap;

  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.reduceStock && product.stock <= 0;

    return InkWell(
      onTap: outOfStock ? null : () => onTap(product),
      borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
      child: Opacity(
        opacity: outOfStock ? .5 : 1,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSizes.radiusSmall),
                  child: SizedBox(
                    width: double.infinity,
                    child: product.imageUrl.isNotEmpty
                        ? Image.network(
                            product.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _placeholder(),
                          )
                        : _placeholder(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                formatCurrency(product.price),
                style: AppText.caption.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (product.reduceStock) ...[
                const SizedBox(height: 2),
                Text(
                  outOfStock ? "Stok habis" : "Stok ${product.stock}",
                  style: AppText.caption.copyWith(
                    fontSize: 10,
                    color: outOfStock ? AppColors.danger : AppColors.textHint,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.textHint.withValues(alpha: .12),
      alignment: Alignment.center,
      child: const Icon(
        Icons.inventory_2_outlined,
        size: 26,
        color: AppColors.textHint,
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  final CartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;
  final VoidCallback onEditNote;
  final VoidCallback onEditAddons;

  const _CartRow({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onEditNote,
    required this.onEditAddons,
  });

  @override
  Widget build(BuildContext context) {
    final hasNote = item.note != null;
    final hasAddons = item.addons.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.radiusMedium),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onEditNote,
                  borderRadius: BorderRadius.circular(6),
                  child: Text(
                    item.product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Tooltip(
                message: hasAddons
                    ? "Edit item tambahan"
                    : "Tambah item tambahan",
                child: InkWell(
                  onTap: onEditAddons,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      hasAddons
                          ? Icons.add_box_rounded
                          : Icons.add_box_outlined,
                      size: 16,
                      color: hasAddons
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              Tooltip(
                message: hasNote ? "Edit catatan" : "Tambah catatan",
                child: InkWell(
                  onTap: onEditNote,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      hasNote
                          ? Icons.sticky_note_2_rounded
                          : Icons.note_add_outlined,
                      size: 16,
                      color: hasNote
                          ? AppColors.primary
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (hasNote) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: onEditNote,
              borderRadius: BorderRadius.circular(6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.subdirectory_arrow_right_rounded,
                    size: 14,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      item.note!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (hasAddons) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: onEditAddons,
              borderRadius: BorderRadius.circular(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final addon in item.addons)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.add_rounded,
                            size: 13,
                            color: AppColors.textHint,
                          ),
                          Expanded(
                            child: Text(
                              "${addon.product.name} x${addon.quantity}",
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption,
                            ),
                          ),
                          Text(
                            formatCurrency(addon.lineTotal),
                            style: AppText.caption,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatCurrency(item.product.price), style: AppText.caption),
              Row(
                children: [
                  _qtyButton(Icons.remove_rounded, onDecrement),
                  SizedBox(
                    width: 28,
                    child: Text(
                      "${item.quantity}",
                      textAlign: TextAlign.center,
                      style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  _qtyButton(Icons.add_rounded, onIncrement),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Subtotal", style: AppText.caption),
              Text(
                formatCurrency(item.lineTotal),
                style: AppText.caption.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 13, color: AppColors.textSecondary),
      ),
    );
  }
}
