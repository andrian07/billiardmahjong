/// Maps an Access module `code` (from Access/menu_list_no_pagging) to the
/// sidebar `menuKey`(s) it should unlock. The backend's permission modules
/// don't all share the sidebar's naming, and "Laporan" is a single code
/// covering the four separate report pages. Codes not listed here are
/// assumed to equal their menuKey directly (e.g. "meja", "produk").
const Map<String, List<String>> menuCodeAliases = {
  'master_member': ['pelanggan'],
  'master_pengguna': ['pengguna'],
  'master_role': ['role'],
  'master_promo': ['promo'],
  'harga_meja': ['pengaturan'],
  'tukar_point': ['setting_point_exchange'],
  'Laporan': [
    'laporan_billing',
    'laporan_mahjong',
    'laporan_cafe',
    'laporan_saldo',
    'laporan_stok',
    'laporan_pembelian',
  ],
};

Set<String> menuKeysForAccessCode(String code) {
  return (menuCodeAliases[code] ?? [code]).toSet();
}
