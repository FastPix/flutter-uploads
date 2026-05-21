import 'dart:convert';

import 'package:http/http.dart' as http;

/// Calls the FastPix Direct Upload API to mint a signed URL.
///
/// In a production app the token + secret should NEVER live in the client;
/// proxy this through your own backend. They are inlined here only so the
/// example is runnable end-to-end with minimal setup.
class SignedUrlService {
  SignedUrlService({required this.tokenId, required this.secretKey});

  final String tokenId;
  final String secretKey;

  static const String _apiBaseUrl =
      'https://api.fastpix.com/v1/on-demand/upload';

  /// Requests a signed URL from FastPix and returns just the `url` field.
  Future<String> generateSignedUrl({
    Map<String, dynamic>? metadata,
    String corsOrigin = '*',
    String accessPolicy = 'public',
    String maxResolution = '1080p',
  }) async {
    final credentials = '$tokenId:$secretKey';
    final auth = 'Basic ${base64.encode(utf8.encode(credentials))}';

    print("Url: $_apiBaseUrl");
    final response = await http.post(
      Uri.parse(_apiBaseUrl),
      headers: {
        'Authorization': auth,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'corsOrigin': corsOrigin,
        'pushMediaSettings': {
          'metadata': metadata ?? {'uploadedBy': 'flutter_example_app'},
          'accessPolicy': accessPolicy,
          'maxResolution': maxResolution,
        },
      }),
    );

    if (response.statusCode != 201) {
      throw Exception(
        'Failed to generate signed URL (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    print("Response: $decoded");
    final data = decoded['data'] as Map<String, dynamic>?;
    final url = data?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('FastPix response missing `data.url`: ${response.body}');
    }
    return url;
  }
}
