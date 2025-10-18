// lib/admin_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  List<Map<String, dynamic>> _pendingUsers = [];

  @override
  void initState() {
    super.initState();
    _loadPendingUsers();
  }

  Future<void> _loadPendingUsers() async {
    final response = await Supabase.instance.client
        .from('profiles')
        .select()
        .eq('status', 'pending')
        .order('created_at');

    setState(() {
      _pendingUsers = List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> _approveUser(String userId) async {
    await Supabase.instance.client
        .from('profiles')
        .update({'status': 'approved'})
        .eq('id', userId);

    // TODO: Envoyer un email de notification à l'utilisateur

    _loadPendingUsers();
  }

  Future<void> _rejectUser(String userId) async {
    await Supabase.instance.client
        .from('profiles')
        .update({'status': 'rejected'})
        .eq('id', userId);

    _loadPendingUsers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Demandes d\'inscription')),
      body: ListView.builder(
        itemCount: _pendingUsers.length,
        itemBuilder: (context, index) {
          final user = _pendingUsers[index];
          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              title: Text('${user['first_name']} ${user['last_name']}'),
              subtitle: Text(user['email'] ?? ''),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _approveUser(user['id']),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _rejectUser(user['id']),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}