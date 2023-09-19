import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_svg/flutter_svg.dart';

const FlutterAppAuth appAuth = FlutterAppAuth();
const FlutterSecureStorage secureStorage = FlutterSecureStorage();

/// For a real-world app, this should be an Internet-facing URL to FusionAuth.
/// If you are running FusionAuth locally and just want to test the app, you can
/// specify a local IP address (if the device is connected to the same network
/// as the computer running FusionAuth) or even use ngrok to expose your
/// instance to the Internet temporarily.
const String FUSIONAUTH_DOMAIN = 'your-fusionauth-public-url';
const String FUSIONAUTH_SCHEME = 'https';
const String FUSIONAUTH_CLIENT_ID = 'e9fdb985-9173-4e01-9d73-ac2d60d1dc8e';
const String FUSIONAUTH_REDIRECT_URI =
    'com.fusionauth.flutterdemo://login-callback';
const String FUSIONAUTH_LOGOUT_REDIRECT_URI =
    'com.fusionauth.flutterdemo://logout-callback';
const String FUSIONAUTH_ISSUER = '$FUSIONAUTH_SCHEME://$FUSIONAUTH_DOMAIN';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  bool isBusy = false;
  bool isLoggedIn = false;
  String? errorMessage;
  String? email;

  @override
  void initState() {
    super.initState();
    initAction();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FusionAuth on Flutter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primaryColor: const Color(0xFF085b21)),
      home: Scaffold(
        body: Center(
          child: isBusy
              ? const CircularProgressIndicator()
              : isLoggedIn
                  ? ChangeCalculatorPage(logoutAction, email)
                  : Login(loginAction, errorMessage),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> getUserDetails(String accessToken) async {
    final http.Response response = await http.get(
      Uri.parse('$FUSIONAUTH_SCHEME://$FUSIONAUTH_DOMAIN/oauth2/userinfo'),
      headers: <String, String>{'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get user details');
    }
  }

  Future<void> loginAction() async {
    setState(() {
      isBusy = true;
      errorMessage = '';
    });

    try {
      final AuthorizationTokenResponse? result =
          await appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          FUSIONAUTH_CLIENT_ID,
          FUSIONAUTH_REDIRECT_URI,
          issuer: FUSIONAUTH_ISSUER,
          scopes: <String>['openid', 'offline_access'],
        ),
      );
      if (result != null) {
        final Map<String, dynamic> profile =
            await getUserDetails(result.accessToken!);

        debugPrint('response: $profile');
        await secureStorage.write(
            key: 'refresh_token', value: result.refreshToken);
        await secureStorage.write(key: 'id_token', value: result.idToken);
        setState(() {
          isBusy = false;
          isLoggedIn = true;
          email = profile['email'];
        });
      }
    } on Exception catch (e, s) {
      debugPrint('login error: $e - stack: $s');

      setState(() {
        isBusy = false;
        isLoggedIn = false;
        errorMessage = e.toString();
      });
    }
  }

  Future<void> initAction() async {
    final String? storedRefreshToken =
        await secureStorage.read(key: 'refresh_token');
    if (storedRefreshToken == null) {
      return;
    }

    setState(() {
      isBusy = true;
    });

    try {
      final TokenResponse? response = await appAuth.token(TokenRequest(
        FUSIONAUTH_CLIENT_ID,
        FUSIONAUTH_REDIRECT_URI,
        issuer: FUSIONAUTH_ISSUER,
        refreshToken: storedRefreshToken,
        scopes: <String>['openid', 'offline_access'],
      ));

      if (response != null) {
        final Map<String, dynamic> profile =
            await getUserDetails(response.accessToken!);

        await secureStorage.write(
            key: 'refresh_token', value: response.refreshToken);

        setState(() {
          isBusy = false;
          isLoggedIn = true;
          email = profile['email'];
        });
      }
    } on Exception catch (e, s) {
      debugPrint('error on refresh token: $e - stack: $s');
      await logoutAction();
    }
  }

  Future<void> logoutAction() async {
    final String? storedIdToken = await secureStorage.read(key: 'id_token');
    if (storedIdToken == null) {
      debugPrint(
          'Could not retrieve id_token for actual logout. Deleting local cookies only...');
    } else {
      try {
        await appAuth.endSession(EndSessionRequest(
            idTokenHint: storedIdToken,
            postLogoutRedirectUrl: FUSIONAUTH_LOGOUT_REDIRECT_URI,
            issuer: FUSIONAUTH_ISSUER,
            allowInsecureConnections: FUSIONAUTH_SCHEME != 'https'));
      } catch (err) {
        debugPrint('logout error: $err');
      }
    }
    await secureStorage.deleteAll();
    setState(() {
      isLoggedIn = false;
      isBusy = false;
    });
  }
}

class Login extends StatelessWidget {
  final Future<void> Function() loginAction;
  final String? loginError;

  const Login(this.loginAction, this.loginError, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            SvgPicture.asset(
              'assets/example_bank_logo.svg',
              width: 150,
              height: 100,
            ),
            const SizedBox(
              height: 30,
            ),
            Row(
              children: [
                Expanded(
                    child: ElevatedButton(
                  onPressed: () async {
                    await loginAction();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF085b21),
                  ),
                  child: const Text('Login'),
                )),
              ],
            ),
            const SizedBox(
              height: 30,
            ),
            Text(
              loginError ?? '',
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ));
  }
}

class ChangeCalculatorPage extends StatefulWidget {
  final Future<void> Function() logoutAction;
  final String? email;

  const ChangeCalculatorPage(this.logoutAction, this.email, {Key? key})
      : super(key: key);

  @override
  _ChangeCalculatorPageState createState() => _ChangeCalculatorPageState();
}

class _ChangeCalculatorPageState extends State<ChangeCalculatorPage> {
  final TextEditingController _changeController = TextEditingController();
  String _result = 'We make change for \$0 with 0 nickels and 0 pennies!';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SvgPicture.asset(
            'assets/example_bank_logo.svg',
            width: 150,
            height: 100,
          ),
          const SizedBox(height: 40),
          Text('Welcome: ${widget.email}'),
          const SizedBox(height: 32),
          Text(
            _result,
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _changeController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount in USD',
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF085b21)),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Color(0xFF085b21)),
              ),
              labelStyle: TextStyle(color: Color(0xFF085b21)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    calculateChange();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF085b21),
                  ),
                  child: const Text('Make Change'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    await widget.logoutAction();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF085b21),
                  ),
                  child: const Text('Logout'),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  void calculateChange() {
    try {
      double totalValue = double.tryParse(_changeController.text) ?? 0;
      int totalCents = (totalValue * 100).toInt();
      int nickels = totalCents ~/ 5;
      int pennies = totalCents % 5;
      setState(() {
        _result =
            'We make change for \$${_changeController.text} with $nickels nickels and $pennies pennies!';
      });
    } catch (e) {
      setState(() {
        _result = 'Please enter a valid number.';
      });
    }
  }

  @override
  void dispose() {
    _changeController.dispose();
    super.dispose();
  }
}
