import 'package:flutter_test/flutter_test.dart';
import 'package:organizacional/features/auth/login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('AuthRetryableFetchException (queda de rede) tem prioridade sobre AuthException', () {
    // AuthRetryableFetchException extends AuthException: se checarmos
    // AuthException primeiro, uma queda de conexão vira erroneamente
    // "E-mail ou senha incorretos.".
    expect(
      authErrorMessage(AuthRetryableFetchException(message: 'network')),
      'Não foi possível conectar ao servidor.',
    );
  });

  test('AuthException comum (credenciais erradas) mostra a mensagem específica', () {
    expect(
      authErrorMessage(const AuthApiException('Invalid login credentials')),
      'E-mail ou senha incorretos.',
    );
  });

  test('erro desconhecido mostra a mensagem de conexão', () {
    expect(authErrorMessage(Exception('boom')), 'Não foi possível conectar ao servidor.');
  });
}
