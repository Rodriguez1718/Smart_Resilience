import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isSaving = false;
  String? _guardianDocId; // Store the guardian document ID
  String? _displayName;
  String? _phoneNumber;
  String? _photoUrl;
  String _selectedRole = 'Parent'; // Default role
  String? _childName; // NEW: Child's name
  String? _childAge; // NEW: Child's age
  XFile? _pickedImage;
  List<Map<String, String>> _emergencyContacts =
      []; // NEW: Emergency contacts list
  final TextEditingController _emergencyNameController =
      TextEditingController();
  final TextEditingController _emergencyPhoneController =
      TextEditingController();

  // Guardian role options
  final List<String> _guardianRoles = [
    'Parent',
    'Guardian',
    'Sibling',
    'Grandparent',
    'Aunt/Uncle',
    'Caregiver',
    'Other',
  ];

  @override
  void dispose() {
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _loadGuardianDocId();
    await _loadProfile();
    await _loadEmergencyContacts();
  }

  Future<void> _loadGuardianDocId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final docId = prefs.getString('guardianDocId');
      if (docId != null && docId.isNotEmpty) {
        setState(() {
          _guardianDocId = docId;
        });
        print('✅ ProfilePage: Loaded guardian doc ID: $docId');
      }
    } catch (e) {
      print('❌ ProfilePage: Error loading guardian doc ID: $e');
    }
  }

  // NEW: Add emergency contact
  Future<void> _addEmergencyContact() async {
    if (_emergencyNameController.text.isEmpty ||
        _emergencyPhoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter name and phone number')),
      );
      return;
    }

    if (_guardianDocId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_guardianDocId)
          .collection('emergency_contacts')
          .add({
            'name': _emergencyNameController.text.trim(),
            'phone': _normalizePhoneNumber(_emergencyPhoneController.text),
            'createdAt': FieldValue.serverTimestamp(),
          });

      _emergencyNameController.clear();
      _emergencyPhoneController.clear();

      await _loadEmergencyContacts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Emergency contact added')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error adding contact: $e')));
    }
  }

  // NEW: Delete emergency contact
  Future<void> _deleteEmergencyContact(String contactId) async {
    if (_guardianDocId == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_guardianDocId)
          .collection('emergency_contacts')
          .doc(contactId)
          .delete();

      await _loadEmergencyContacts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Emergency contact deleted')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error deleting contact: $e')));
    }
  }

  // NEW: Normalize phone number to E.164 format (+639XXXXXXXXX) for Philippines
  String _normalizePhoneNumber(String input) {
    String phone = input.trim();
    if (phone.isEmpty) return phone;
    phone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (phone.startsWith('+')) return phone;
    if (phone.startsWith('0')) phone = phone.substring(1);
    if (phone.length == 10 && phone.startsWith('9')) {
      return '+63$phone';
    }
    return '+63$phone';
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _displayName = user.displayName ?? user.phoneNumber ?? 'Guardian';
      _phoneNumber = user.phoneNumber ?? 'N/A';
    });

    if (_guardianDocId == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('guardians')
        .doc(_guardianDocId)
        .get();
    if (doc.exists && doc.data() != null) {
      final data = doc.data() as Map<String, dynamic>;
      setState(() {
        _displayName = data['fullName'] ?? _displayName;
        _phoneNumber = data['phoneNumber'] ?? _phoneNumber;
        _selectedRole = data['role'] ?? 'Parent';
        _photoUrl = data['photoUrl'] as String?;
      });
    }

    // NEW: Load paired device info (child name and age)
    try {
      final pairedDeviceDoc = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_guardianDocId)
          .collection('paired_device')
          .doc('device_info')
          .get();

      if (pairedDeviceDoc.exists && pairedDeviceDoc.data() != null) {
        final pairedData = pairedDeviceDoc.data() as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _childName = pairedData['childName'] as String?;
            _childAge = pairedData['childAge'] as String?;
          });
        }
      }
    } catch (e) {
      print('Error loading paired device info: $e');
    }
  }

  Future<void> _loadEmergencyContacts() async {
    if (_guardianDocId == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_guardianDocId)
          .collection('emergency_contacts')
          .orderBy('createdAt', descending: false)
          .get();

      if (mounted) {
        setState(() {
          _emergencyContacts = snapshot.docs
              .map(
                (doc) => {
                  'id': doc.id,
                  'name': (doc.data()['name'] ?? '') as String,
                  'phone': (doc.data()['phone'] ?? '') as String,
                },
              )
              .toList();
        });
      }
    } catch (e) {
      print('Error loading emergency contacts: $e');
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

      if (_guardianDocId == null) return;

      // Ensure the document exists by creating it with merge: true
      await FirebaseFirestore.instance
          .collection('guardians')
          .doc(_guardianDocId)
          .set({
            'fullName': _displayName ?? user.phoneNumber ?? 'Guardian',
            'phoneNumber': _phoneNumber ?? user.phoneNumber,
            'role': _selectedRole,
            'photoUrl': localImagePath, // This will now be a local file path
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // NEW: Save paired device info (child name and age)
      if (_childName != null || _childAge != null) {
        await FirebaseFirestore.instance
            .collection('guardians')
            .doc(_guardianDocId)
            .collection('paired_device')
            .doc('device_info')
            .set({
              'childName': _childName,
              'childAge': _childAge,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
      }

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
          const SizedBox(height: 16),
          TextField(
            controller: TextEditingController(text: _phoneNumber),
            onChanged: (v) => _phoneNumber = v,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              hintText: 'e.g., +639123456789',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // NEW: Child's Name field
          TextField(
            controller: TextEditingController(text: _childName),
            onChanged: (v) => _childName = v,
            decoration: const InputDecoration(
              labelText: "Child's Name",
              hintText: 'e.g., John',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          // NEW: Child's Age field
          TextField(
            controller: TextEditingController(text: _childAge),
            onChanged: (v) => _childAge = v,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: "Child's Age",
              hintText: 'e.g., 12',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Guardian Role',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: DropdownButton<String>(
                  value: _selectedRole,
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedRole = newValue ?? 'Parent';
                    });
                  },
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: _guardianRoles.map<DropdownMenuItem<String>>((
                    String value,
                  ) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // NEW: Emergency Contacts Section
          _buildEmergencyContactsSection(),
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

  // NEW: Build emergency contacts section
  Widget _buildEmergencyContactsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Emergency Contacts',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            Text(
              '(Notified on panic)',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Add new contact form
        Card(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: _emergencyNameController,
                  decoration: InputDecoration(
                    labelText: 'Contact Name',
                    hintText: 'e.g., Mom',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _emergencyPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    hintText: 'e.g., +639123456789',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _addEmergencyContact,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Contact'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // List of existing emergency contacts
        if (_emergencyContacts.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No emergency contacts added yet',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _emergencyContacts.length,
            itemBuilder: (context, index) {
              final contact = _emergencyContacts[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepPurple.shade100,
                    child: Text(
                      contact['name']![0].toUpperCase(),
                      style: TextStyle(
                        color: Colors.deepPurple.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(contact['name'] ?? ''),
                  subtitle: Text(contact['phone'] ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Delete Contact?'),
                          content: Text(
                            'Remove ${contact['name']} from emergency contacts?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () {
                                _deleteEmergencyContact(contact['id']!);
                                Navigator.pop(context);
                              },
                              child: const Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
