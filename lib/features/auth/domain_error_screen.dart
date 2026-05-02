import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sunrintodo/core/constants/app_constants.dart';

class DomainErrorScreen extends StatelessWidget {
  const DomainErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.block, size: 64, color: Colors.red),
              const SizedBox(height: 24),
              const Text(
                '접근 불가',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                '${AppConstants.schoolDomain}\n계정으로만 로그인할 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () => context.go('/auth'),
                child: const Text('돌아가기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
