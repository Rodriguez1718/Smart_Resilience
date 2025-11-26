// lib/widgets/profile_avatar.dart

import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:smart_resilience_app/screens/profile_page.dart';

typedef ProfileUpdatedCallback = void Function(bool? updated);

class ProfileAvatar extends StatelessWidget {
  final String? photoPath;
  final String? displayName;
  final double radius;
  final ProfileUpdatedCallback? onProfileUpdated;

  const ProfileAvatar({
    Key? key,
    this.photoPath,
    this.displayName,
    this.radius = 18,
    this.onProfileUpdated,
  }) : super(key: key);

  String _initial() {
    if (displayName != null && displayName!.isNotEmpty)
      return displayName![0].toUpperCase();
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email?.isNotEmpty == true) return user!.email![0].toUpperCase();
    if (user?.phoneNumber?.isNotEmpty == true)
      return user!.phoneNumber![0].toUpperCase();
    return 'G';
  }

  @override
  Widget build(BuildContext context) {
    final initial = _initial();

    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: () async {
        final updated = await Navigator.of(
          context,
        ).push<bool?>(MaterialPageRoute(builder: (_) => const ProfilePage()));
        if (onProfileUpdated != null) onProfileUpdated!(updated);
      },
      child: CircleAvatar(
        backgroundColor: Colors.deepPurple[400],
        radius: radius,
        backgroundImage: photoPath != null && photoPath!.isNotEmpty
            ? FileImage(File(photoPath!))
            : null,
        child: (photoPath == null || photoPath!.isEmpty)
            ? Text(
                initial,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )
            : null,
      ),
    );
  }
}
