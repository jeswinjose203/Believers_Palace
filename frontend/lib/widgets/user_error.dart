import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/api_client.dart';
import '../l10n/app_locale.dart';

String userErrorMessage(
  Object? error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is String) return error;
  if (error is SocketException || error is http.ClientException) {
    return 'Could not connect. Check your internet connection and try again.';
  }
  if (error is TimeoutException) {
    return 'The request took too long. Please try again.';
  }
  if (error is ApiException) {
    if (error.code == 'upload_busy' ||
        error.code == 'phone_verification_unavailable') {
      return error.message;
    }
    if (error.statusCode == 429) {
      return 'Too many attempts. Wait a moment and try again.';
    }
    if (error.statusCode >= 400 &&
        error.statusCode < 500 &&
        error.message.trim().isNotEmpty &&
        error.message != 'Request failed') {
      return error.message;
    }
  }
  return fallback;
}

Future<void> showUserError(
  BuildContext context,
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) =>
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('Something went wrong')),
        content:
            Text(dialogContext.tr(userErrorMessage(error, fallback: fallback))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.tr('Close')),
          ),
        ],
      ),
    );
