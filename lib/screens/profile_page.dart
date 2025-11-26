import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isSaving = false;
  String? _displayName;
  String? _photoUrl;
  XFile? _pickedImage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _displayName = user.displayName ?? user.phoneNumber ?? 'Guardian';
    });
    final doc = await FirebaseFirestore.instance
        .collection('guardians')
        .doc(user.uid)
        .get();
    if (doc.exists && doc.data() != null) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _displayName = data['fullName'] ?? _displayName;
        _photoUrl = data['photoUrl'] as String?;
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _pickedImage = image;
      });
    }
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _isSaving = true;
    });

    String? localImagePath = _photoUrl;
    try {
      if (_pickedImage != null) {
        try {
          final directory = await getApplicationDocumentsDirectory();
          // Use a timestamped filename so the saved path changes each time
          // — this avoids Flutter's image cache returning the old image when
          // the file is overwritten at the same path.
          final fileName =
              '${user.uid}_profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final savedImagePath = path.join(directory.path, fileName);

          // Evict any cached image for the previous local path so the UI
          // doesn't show a stale image (best-effort, ignore failures).
          try {
            if (_photoUrl != null && _photoUrl!.isNotEmpty) {
              await FileImage(File(_photoUrl!)).evict();
            }
          } catch (e) {
            // ignore cache eviction errors
            print('Image cache eviction failed: $e');
          }

          // Use readAsBytes + writeAsBytes which works across platforms
          final bytes = await _pickedImage!.readAsBytes();
          final savedFile = File(savedImagePath);
          await savedFile.create(recursive: true);
          await savedFile.writeAsBytes(bytes, flush: true);

          localImagePath = savedImagePath;
        } catch (storageError) {
          print('Local storage error: $storageError');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Failed to save image locally. Profile will be saved without photo.',
              ),
            ),
          );
          // Continue without photo
          localImagePath = _photoUrl;
        }
      }

      // Ensure the document exists by creating it with merge: true
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(user.uid)
          .set({
            'fullName': _displayName ?? user.phoneNumber ?? 'Guardian',
            'photoUrl': localImagePath, // This will now be a local file path
            'phoneNumber': user.phoneNumber,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Profile updated')));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update profile: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 48,
                  backgroundColor: Colors.deepPurple[400],
                  backgroundImage: _pickedImage != null
                      ? (kIsWeb
                            ? NetworkImage(_pickedImage!.path)
                            : FileImage(File(_pickedImage!.path))
                                  as ImageProvider)
                      : (_photoUrl != null && _photoUrl!.isNotEmpty
                            ? FileImage(File(_photoUrl!))
                            : null),
                  child:
                      (_pickedImage == null &&
                          (_photoUrl == null || _photoUrl!.isEmpty))
                      ? Text(
                          (_displayName?.isNotEmpty == true
                              ? _displayName![0].toUpperCase()
                              : 'G'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: InkWell(
                    onTap: _pickImage,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const Icon(Icons.camera_alt, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: TextEditingController(text: _displayName),
            onChanged: (v) => _displayName = v,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text('Save Changes'),
            ),
          ),
        ],
      ),
    );
  }
}
