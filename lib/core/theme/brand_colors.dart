import 'package:flutter/painting.dart';

/// The website's palette: saffron and turmeric warmth, with a deep curry-leaf green for actions.
abstract final class Brand {
  static const cream = Color(0xFFFDF8F0);
  static const ink = Color(0xFF1C1917);

  static const saffron50 = Color(0xFFFFF7ED);
  static const saffron100 = Color(0xFFFFEDD5);
  static const saffron200 = Color(0xFFFED7AA);
  static const saffron400 = Color(0xFFFB923C);
  static const saffron500 = Color(0xFFF97316);
  static const saffron600 = Color(0xFFEA580C);
  static const saffron700 = Color(0xFFC2410C);

  static const leaf50 = Color(0xFFF0FDF4);
  static const leaf600 = Color(0xFF15803D);
  static const leaf700 = Color(0xFF166534);
  static const leaf800 = Color(0xFF14532D);

  static const chilli = Color(0xFFB91C1C);

  // Warm greys (Tailwind's stone), for text and hairlines.
  static const stone50 = Color(0xFFFAFAF9);
  static const stone100 = Color(0xFFF5F5F4);
  static const stone200 = Color(0xFFE7E5E4);
  static const stone300 = Color(0xFFD6D3D1);
  static const stone400 = Color(0xFFA8A29E);
  static const stone500 = Color(0xFF78716C);
  static const stone600 = Color(0xFF57534E);
  static const stone700 = Color(0xFF44403C);
  static const stone800 = Color(0xFF292524);
  static const stone900 = Color(0xFF1C1917);
  static const stone950 = Color(0xFF0C0A09);

  /// The veg mark's green and the non-veg mark's red, as on Indian food packaging.
  static const vegGreen = Color(0xFF15803D);
  static const nonVegRed = Color(0xFFB91C1C);
}
