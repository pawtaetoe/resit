import 'package:flutter_test/flutter_test.dart';
import 'package:resit/features/lms/data/lms_service.dart';

void main() {
  test('links from xSiTe resolve on xSiTe', () {
    expect(LmsService.onXsite('/d2l/api/le/1.75/123/news/?bookmark=5').toString(),
        'https://xsite.singaporetech.edu.sg/d2l/api/le/1.75/123/news/?bookmark=5');
    expect(LmsService.onXsite('https://xsite.singaporetech.edu.sg/x').host, 'xsite.singaporetech.edu.sg');
  });

  test('links that leave xSiTe are refused', () {
    expect(() => LmsService.onXsite('https://attacker.example/steal'), throwsFormatException);
    expect(() => LmsService.onXsite('//attacker.example/steal'), throwsFormatException);
    expect(() => LmsService.onXsite('http://xsite.singaporetech.edu.sg/x'), throwsFormatException);
    expect(() => LmsService.onXsite('https://in4sit.singaporetech.edu.sg/x'), throwsFormatException);
  });
}
