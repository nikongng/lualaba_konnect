import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> with TickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Utilisateurs'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Classiques'),
            Tab(text: 'Professionnels'),
            Tab(text: 'Entreprises'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUserList('classic_users'),
          _buildUserList('pro_users'),
          _buildUserList('enterprise_users'),
        ],
      ),
    );
  }

  Widget _buildUserList(String collection) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection(collection).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Erreur: ${snapshot.error}'));
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
        }

        final users = snapshot.data!.docs;

        if (users.isEmpty) {
          return const Center(child: Text('Aucun utilisateur trouvé.'));
        }

        return ListView.builder(
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.all(8.0),
              child: ListTile(
                title: Text('${user['firstName']} ${user['lastName']}'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Email: ${user['email']}'),
                    Text('Téléphone: ${user['phone']}'),
                    Text('Adresse: ${user['address']}'),
                    Text('Statut upload: ${user['uploadStatus'] ?? 'N/A'}'),
                    if (user['profileType'] == 1 || user['profileType'] == 2) ...[
                      Text('Bio: ${user['bio'] ?? 'N/A'}'),
                      if (user['profileType'] == 2) Text('RCCM: ${user['rccm'] ?? 'N/A'}'),
                    ],
                  ],
                ),
                trailing: Icon(
                  user['uploadStatus'] == 'complete' ? Icons.check_circle : Icons.error,
                  color: user['uploadStatus'] == 'complete' ? Colors.green : Colors.red,
                ),
              ),
            );
          },
        );
      },
    );
  }
}