import 'api_client.dart';

class FaceService {
  final ApiClient client;
  FaceService(this.client);

  Future<({bool enrolled, bool allowLogin})> statusInfo() async {
    final data = await client.get('/api/face/status');
    return (
      enrolled: data['enrolled'] == true,
      allowLogin: data['allowLogin'] == true,
    );
  }

  Future<bool> status() async => (await statusInfo()).enrolled;
  Future<String> requestOtp() async =>
      (await client.post('/api/face/request-otp'))['challengeId'].toString();
  Future<void> enroll(
    String challenge,
    String code,
    String image,
    String confirmImage, {
    bool allowLogin = false,
  }) async {
    await client.post(
      '/api/face/enroll',
      body: {
        'challengeId': challenge,
        'code': code.trim(),
        'image': image,
        'confirmImage': confirmImage,
        'consent': true,
        'allowLogin': allowLogin,
      },
    );
  }

  Future<String> verify(String image, String purpose) async =>
      (await client.post(
        '/api/face/verify',
        body: {'image': image, 'purpose': purpose},
      ))['proof'].toString();
  Future<void> remove(String challenge, String code) async {
    await client.post(
      '/api/face/remove',
      body: {'challengeId': challenge, 'code': code.trim()},
    );
  }
}
