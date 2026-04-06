import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lualaba_konnect/core/supabase_service.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class RevenueManagementPage extends StatefulWidget {
  const RevenueManagementPage({super.key});

  @override
  State<RevenueManagementPage> createState() => _RevenueManagementPageState();
}

enum _RevenueRole { none, agent, admin }

enum _AgentView { menu, newTransaction, pending, history, settings }

enum _AdminView { dashboard, transactions, reports, agents }

class _RevenueManagementPageState extends State<RevenueManagementPage> {
  static const Color _accent = Color(0xFF0B5FFF);
  static const Color _success = Color(0xFF16A34A);
  static const Color _warning = Color(0xFFFF8A00);
  static const Color _danger = Color(0xFFE53935);

  final _repository = _RevenueRepository();
  final _currency = NumberFormat.currency(
    locale: 'fr_FR',
    symbol: 'FC',
    decimalDigits: 0,
  );

  final _agentLoginKey = GlobalKey<FormState>();
  final _adminLoginKey = GlobalKey<FormState>();
  final _transactionKey = GlobalKey<FormState>();
  final _agentFormKey = GlobalKey<FormState>();

  final _agentIdentifierCtrl = TextEditingController();
  final _agentPasswordCtrl = TextEditingController();
  final _adminLoginCtrl = TextEditingController();
  final _adminPasswordCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _taxpayerCtrl = TextEditingController();
  final _agentNameCtrl = TextEditingController();
  final _agentPhoneCtrl = TextEditingController();
  final _agentCommuneCtrl = TextEditingController();
  final _adminNameCtrl = TextEditingController();
  final _adminRoleCtrl = TextEditingController(text: 'Administration');
  final _newAdminLoginCtrl = TextEditingController();
  final _newAdminPasswordCtrl = TextEditingController();
  final _currentAdminPasswordCtrl = TextEditingController();
  final _newOwnPasswordCtrl = TextEditingController();
  final _confirmOwnPasswordCtrl = TextEditingController();

  _RevenueRole _role = _RevenueRole.none;
  _AgentView _agentView = _AgentView.menu;
  _AdminView _adminView = _AdminView.dashboard;

  _RevenueAgent? _currentAgent;
  _RevenueAdmin? _currentAdmin;
  _RevenueTransaction? _editingTransaction;
  _RevenueAgent? _editingAgent;

  bool _busy = false;
  bool _bootstrapping = true;
  bool _biometricReady = false;
  bool _newAdminIsSuperAdmin = false;

  String _selectedTransactionType = 'Taxe';
  String _selectedAgentGender = 'Masculin';
  String _historyStatus = 'TOUT';
  String _historyType = 'TOUT';
  DateTime? _historyDate;
  String _adminStatus = 'TOUT';
  String _currentTransactionNumber = '';
  DateTime _currentTransactionDate = DateTime.now();

  Uint8List? _agentPhotoBytes;

  List<_RevenueTransaction> _pendingTransactions = const [];
  List<_RevenueTransaction> _agentTransactions = const [];
  List<_RevenueTransaction> _adminTransactions = const [];
  List<_RevenueAgent> _agents = const [];
  List<_RevenueAdmin> _admins = const [];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _agentIdentifierCtrl.dispose();
    _agentPasswordCtrl.dispose();
    _adminLoginCtrl.dispose();
    _adminPasswordCtrl.dispose();
    _amountCtrl.dispose();
    _taxpayerCtrl.dispose();
    _agentNameCtrl.dispose();
    _agentPhoneCtrl.dispose();
    _agentCommuneCtrl.dispose();
    _adminNameCtrl.dispose();
    _adminRoleCtrl.dispose();
    _newAdminLoginCtrl.dispose();
    _newAdminPasswordCtrl.dispose();
    _currentAdminPasswordCtrl.dispose();
    _newOwnPasswordCtrl.dispose();
    _confirmOwnPasswordCtrl.dispose();
    super.dispose();
  }

  Color get _bg => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF091118)
      : const Color(0xFFF5F7FB);
  Color get _card => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF101A24)
      : Colors.white;
  Color get _text => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFF3F6FB)
      : const Color(0xFF122033);
  Color get _sub => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFAAB5C4)
      : const Color(0xFF627085);
  Color get _border => Theme.of(context).brightness == Brightness.dark
      ? Colors.white12
      : const Color(0xFFE2E8F0);
  bool get _isSuperAdmin => _currentAdmin?.isSuperAdmin == true;

  Future<void> _bootstrap() async {
    await _repository.ensureBootstrapData();
    final cached = await _repository.loadBiometricAgent();
    final admins = await _repository.loadAdmins();
    if (!mounted) return;
    setState(() {
      _biometricReady = cached != null;
      _admins = admins;
      _bootstrapping = false;
    });
  }

  void _showSnack(String message, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  Future<void> _loadAgentWorkspace(
    _RevenueAgent agent, {
    _AgentView view = _AgentView.menu,
  }) async {
    final pending = await _repository.loadPendingTransactions(agentId: agent.id);
    final history = await _repository.loadTransactions(agentId: agent.id);
    final nextNumber = await _repository.reserveNextTransactionNumber();
    if (!mounted) return;
    setState(() {
      _currentAgent = agent;
      _pendingTransactions = pending;
      _agentTransactions = history;
      _currentTransactionNumber = nextNumber;
      _currentTransactionDate = DateTime.now();
      _editingTransaction = null;
      _agentView = view;
    });
    _amountCtrl.clear();
    _taxpayerCtrl.clear();
    _selectedTransactionType = 'Taxe';
  }

  Future<void> _loadAdminWorkspace(
    _RevenueAdmin admin, {
    _AdminView view = _AdminView.dashboard,
  }) async {
    final transactions = await _repository.loadTransactions();
    final agents = await _repository.loadAgents();
    final admins = await _repository.loadAdmins();
    if (!mounted) return;
    setState(() {
      _currentAdmin = admin;
      _adminTransactions = transactions;
      _agents = agents;
      _admins = admins;
      _adminView = view;
      _editingAgent = null;
    });
    _resetAdminForm();
  }

  Future<void> _refreshAgentData() async {
    final agent = _currentAgent;
    if (agent == null) return;
    final pending = await _repository.loadPendingTransactions(agentId: agent.id);
    final history = await _repository.loadTransactions(agentId: agent.id);
    if (!mounted) return;
    setState(() {
      _pendingTransactions = pending;
      _agentTransactions = history;
    });
  }

  Future<void> _refreshAdminData() async {
    final transactions = await _repository.loadTransactions();
    final agents = await _repository.loadAgents();
    final admins = await _repository.loadAdmins();
    if (!mounted) return;
    setState(() {
      _adminTransactions = transactions;
      _agents = agents;
      _admins = admins;
    });
  }

  Future<void> _handleAgentLogin() async {
    if (!(_agentLoginKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final agent = await _repository.loginAgent(
      identifier: _agentIdentifierCtrl.text.trim(),
      password: _agentPasswordCtrl.text.trim(),
    );
    if (!mounted) return;
    if (agent == null) {
      setState(() => _busy = false);
      _showSnack(
        'Identifiants agent invalides. Cree un agent depuis l espace administration.',
        color: _danger,
      );
      return;
    }
    await _repository.saveBiometricAgent(agent);
    await _loadAgentWorkspace(agent);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _biometricReady = true;
    });
  }

  Future<void> _handleBiometricLogin() async {
    setState(() => _busy = true);
    try {
      final auth = LocalAuthentication();
      final supported = await auth.canCheckBiometrics || await auth.isDeviceSupported();
      if (!supported) {
        if (!mounted) return;
        setState(() => _busy = false);
        _showSnack('La biometrie n est pas disponible sur cet appareil.', color: _warning);
        return;
      }
      final ok = await auth.authenticate(
        localizedReason: 'Confirme ton identite pour ouvrir l espace agent',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      if (!ok) {
        if (!mounted) return;
        setState(() => _busy = false);
        return;
      }
      final cached = await _repository.loadBiometricAgent();
      if (cached == null) {
        if (!mounted) return;
        setState(() => _busy = false);
        _showSnack('Aucun compte agent memorise.', color: _warning);
        return;
      }
      await _loadAgentWorkspace(cached);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _showSnack('Connexion biometrie impossible: $e', color: _danger);
    }
  }

  Future<void> _handleAdminLogin() async {
    if (!(_adminLoginKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final admin = await _repository.loginAdmin(
      login: _adminLoginCtrl.text.trim(),
      password: _adminPasswordCtrl.text.trim(),
    );
    if (!mounted) return;
    if (admin == null) {
      setState(() => _busy = false);
      _showSnack('Identifiants administration invalides.', color: _danger);
      return;
    }
    await _loadAdminWorkspace(admin);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _submitTransaction() async {
    final agent = _currentAgent;
    if (agent == null) return;
    if (!(_transactionKey.currentState?.validate() ?? false)) return;
    final amount = double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      _showSnack('Le montant doit etre superieur a 0.', color: _warning);
      return;
    }

    setState(() => _busy = true);
    final tx = _RevenueTransaction(
      id: _editingTransaction?.id ?? _currentTransactionNumber,
      amount: amount,
      type: _selectedTransactionType,
      taxpayerName: _taxpayerCtrl.text.trim(),
      date: _editingTransaction?.date ?? _currentTransactionDate,
      agentId: agent.id,
      agentName: agent.fullName,
      commune: agent.commune,
      status: 'EN_ATTENTE',
      comment: _editingTransaction?.comment ?? '',
      localOnly: _editingTransaction?.localOnly ?? true,
    );

    late final _RevenueTransaction saved;
    if (_editingTransaction != null && _editingTransaction!.localOnly) {
      saved = await _repository.updatePendingTransaction(tx.copyWith(localOnly: true));
    } else {
      saved = await _repository.saveOrQueueTransaction(tx);
    }

    final nextNumber = await _repository.reserveNextTransactionNumber();
    await _refreshAgentData();
    await _refreshAdminData();
    if (!mounted) return;
    _amountCtrl.clear();
    _taxpayerCtrl.clear();
    setState(() {
      _busy = false;
      _editingTransaction = null;
      _selectedTransactionType = 'Taxe';
      _currentTransactionNumber = nextNumber;
      _currentTransactionDate = DateTime.now();
      _agentView = saved.localOnly ? _AgentView.pending : _AgentView.history;
    });
    _showSnack(
      saved.localOnly
          ? 'Recette enregistree localement. Confirme-la plus tard.'
          : 'Recette envoyee au backend.',
      color: saved.localOnly ? _warning : _success,
    );
  }

  Future<void> _confirmPendingTransaction(_RevenueTransaction transaction) async {
    setState(() => _busy = true);
    final synced = await _repository.confirmPendingTransaction(transaction);
    await _refreshAgentData();
    await _refreshAdminData();
    if (!mounted) return;
    setState(() => _busy = false);
    _showSnack(
      synced
          ? 'Transaction synchronisee avec succes.'
          : 'Synchronisation impossible pour le moment.',
      color: synced ? _success : _warning,
    );
  }

  Future<void> _syncPendingTransactions() async {
    setState(() => _busy = true);
    final count = await _repository.syncPendingTransactions(agentId: _currentAgent?.id);
    await _refreshAgentData();
    await _refreshAdminData();
    if (!mounted) return;
    setState(() => _busy = false);
    _showSnack(
      count > 0
          ? '$count transaction(s) synchronisee(s).'
          : 'Aucune transaction locale synchronisee.',
      color: count > 0 ? _success : _warning,
    );
  }

  void _editPendingTransaction(_RevenueTransaction tx) {
    setState(() {
      _editingTransaction = tx;
      _amountCtrl.text = tx.amount.toStringAsFixed(0);
      _taxpayerCtrl.text = tx.taxpayerName;
      _selectedTransactionType = tx.type;
      _currentTransactionNumber = tx.id;
      _currentTransactionDate = tx.date;
      _agentView = _AgentView.newTransaction;
    });
  }

  Future<void> _pickHistoryDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _historyDate ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (date == null) return;
    setState(() => _historyDate = date);
  }

  Future<void> _pickAgentPhoto() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 55,
        maxWidth: 720,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _agentPhotoBytes = bytes);
    } catch (e) {
      _showSnack('Impossible de charger la photo: $e', color: _danger);
    }
  }

  Future<void> _submitAgentForm() async {
    if (!(_agentFormKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final editing = _editingAgent;
    final saved = await _repository.saveAgent(
      existing: editing,
      fullName: _agentNameCtrl.text.trim(),
      gender: _selectedAgentGender,
      phone: _agentPhoneCtrl.text.trim(),
      commune: _agentCommuneCtrl.text.trim(),
      photoBase64: _agentPhotoBytes == null
          ? editing?.photoBase64
          : base64Encode(_agentPhotoBytes!),
    );
    await _refreshAdminData();
    if (!mounted) return;
    _resetAgentForm();
    setState(() => _busy = false);
    _showSnack(
      editing == null
          ? 'Agent cree: ${saved.identifier} / ${saved.password}'
          : 'Agent mis a jour: ${saved.identifier}',
      color: _success,
    );
  }

  Future<void> _toggleAgentState(_RevenueAgent agent) async {
    setState(() => _busy = true);
    await _repository.toggleAgentEnabled(agent);
    await _refreshAdminData();
    if (!mounted) return;
    setState(() => _busy = false);
    _showSnack(
      agent.enabled ? 'Agent desactive.' : 'Agent reactive.',
      color: agent.enabled ? _warning : _success,
    );
  }

  void _prepareAgentEdit(_RevenueAgent agent) {
    setState(() {
      _editingAgent = agent;
      _agentNameCtrl.text = agent.fullName;
      _agentPhoneCtrl.text = agent.phone;
      _agentCommuneCtrl.text = agent.commune;
      _selectedAgentGender = agent.gender;
      _agentPhotoBytes = agent.photoBase64 == null ? null : base64Decode(agent.photoBase64!);
      _adminView = _AdminView.agents;
    });
  }

  void _resetAgentForm() {
    _editingAgent = null;
    _agentNameCtrl.clear();
    _agentPhoneCtrl.clear();
    _agentCommuneCtrl.clear();
    _selectedAgentGender = 'Masculin';
    _agentPhotoBytes = null;
  }

  void _resetAdminForm() {
    _adminNameCtrl.clear();
    _adminRoleCtrl.text = 'Administration';
    _newAdminLoginCtrl.clear();
    _newAdminPasswordCtrl.clear();
    _newAdminIsSuperAdmin = false;
  }

  Future<void> _submitAdminForm() async {
    final currentAdmin = _currentAdmin;
    if (currentAdmin == null || !_isSuperAdmin) return;
    final name = _adminNameCtrl.text.trim();
    final role = _adminRoleCtrl.text.trim();
    final login = _newAdminLoginCtrl.text.trim();
    final password = _newAdminPasswordCtrl.text.trim();
    if (name.isEmpty || role.isEmpty || login.isEmpty || password.isEmpty) {
      _showSnack('Complete tous les champs admin.', color: _warning);
      return;
    }
    setState(() => _busy = true);
    final saved = await _repository.saveAdmin(
      existing: null,
      name: name,
      role: role,
      login: login,
      password: password,
      isSuperAdmin: _newAdminIsSuperAdmin,
      createdByAdminId: currentAdmin.id,
    );
    await _refreshAdminData();
    if (!mounted) return;
    _resetAdminForm();
    setState(() => _busy = false);
    _showSnack(
      saved == null
          ? 'Impossible de creer cet admin. Le login existe peut-etre deja.'
          : 'Admin ajoute: ${saved.login} (${saved.role})',
      color: saved == null ? _danger : _success,
    );
  }

  Future<void> _changeOwnAdminPassword() async {
    final currentAdmin = _currentAdmin;
    if (currentAdmin == null) return;
    final current = _currentAdminPasswordCtrl.text.trim();
    final next = _newOwnPasswordCtrl.text.trim();
    final confirm = _confirmOwnPasswordCtrl.text.trim();
    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      _showSnack('Complete les champs du mot de passe.', color: _warning);
      return;
    }
    if (current != currentAdmin.password) {
      _showSnack('Mot de passe actuel incorrect.', color: _danger);
      return;
    }
    if (next != confirm) {
      _showSnack('La confirmation ne correspond pas.', color: _danger);
      return;
    }
    if (next.length < 4) {
      _showSnack('Le nouveau mot de passe est trop court.', color: _warning);
      return;
    }
    setState(() => _busy = true);
    final updated = await _repository.saveAdmin(
      existing: currentAdmin,
      name: currentAdmin.name,
      role: currentAdmin.role,
      login: currentAdmin.login,
      password: next,
      isSuperAdmin: currentAdmin.isSuperAdmin,
      createdByAdminId: currentAdmin.createdByAdminId ?? currentAdmin.id,
    );
    await _refreshAdminData();
    if (!mounted) return;
    _currentAdminPasswordCtrl.clear();
    _newOwnPasswordCtrl.clear();
    _confirmOwnPasswordCtrl.clear();
    setState(() {
      _busy = false;
      if (updated != null) {
        _currentAdmin = updated;
      }
    });
    _showSnack(
      updated == null
          ? 'Impossible de modifier le mot de passe.'
          : 'Mot de passe mis a jour.',
      color: updated == null ? _danger : _success,
    );
  }

  void _logoutToRolePicker() {
    setState(() {
      _role = _RevenueRole.none;
      _currentAgent = null;
      _currentAdmin = null;
      _busy = false;
      _agentView = _AgentView.menu;
      _adminView = _AdminView.dashboard;
    });
  }

  List<_RevenueTransaction> get _filteredHistory {
    return _agentTransactions.where((tx) {
      final byStatus = _historyStatus == 'TOUT' || tx.status == _historyStatus;
      final byType = _historyType == 'TOUT' || tx.type == _historyType;
      final byDate = _historyDate == null ||
          (tx.date.year == _historyDate!.year &&
              tx.date.month == _historyDate!.month &&
              tx.date.day == _historyDate!.day);
      return byStatus && byType && byDate;
    }).toList();
  }

  List<_RevenueTransaction> get _filteredAdminTransactions {
    return _adminTransactions.where((tx) {
      return _adminStatus == 'TOUT' || tx.status == _adminStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: _text,
        leading: IconButton(
          onPressed: () {
            if (_role == _RevenueRole.none) {
              Navigator.pop(context);
              return;
            }
            if (_role == _RevenueRole.agent &&
                _currentAgent != null &&
                _agentView != _AgentView.menu) {
              setState(() => _agentView = _AgentView.menu);
              return;
            }
            if (_role == _RevenueRole.admin &&
                _currentAdmin != null &&
                _adminView != _AdminView.dashboard) {
              setState(() => _adminView = _AdminView.dashboard);
              return;
            }
            _logoutToRolePicker();
          },
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Gestion des Recettes'),
            Text(
              _role == _RevenueRole.none
                  ? 'Choix du role'
                  : _role == _RevenueRole.agent
                      ? 'Parcours agent'
                      : 'Parcours administration',
              style: TextStyle(
                color: _sub,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          if (_role != _RevenueRole.none)
            TextButton(
              onPressed: _logoutToRolePicker,
              child: const Text('Changer'),
            ),
        ],
      ),
      body: _bootstrapping
          ? Center(child: CircularProgressIndicator(color: _accent))
          : Stack(
              children: [
                SafeArea(
                  top: false,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 240),
                    child: _buildBody(),
                  ),
                ),
                if (_busy)
                  Container(
                    color: Colors.black.withOpacity(0.16),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: _border),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: _accent),
                          const SizedBox(height: 12),
                          Text(
                            'Traitement en cours...',
                            style: TextStyle(color: _text, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildBody() {
    if (_role == _RevenueRole.none) return _buildRolePicker();
    if (_role == _RevenueRole.agent && _currentAgent == null) return _buildAgentLogin();
    if (_role == _RevenueRole.admin && _currentAdmin == null) return _buildAdminLogin();
    if (_role == _RevenueRole.agent) return _buildAgentWorkspace();
    return _buildAdminWorkspace();
  }

  Widget _buildRolePicker() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _hero(
          title: 'Gestion des Recettes',
          subtitle:
              'Choisis le role qui entre dans le systeme pour ouvrir le bon circuit metier.',
          colors: const [Color(0xFF0B5FFF), Color(0xFF4F46E5)],
          icon: Icons.account_balance_rounded,
        ),
        const SizedBox(height: 18),
        _infoBox(
          icon: Icons.route_rounded,
          text:
              'Ecran d accueil: Agent pour l encaissement terrain, Administration pour le pilotage, la validation et les rapports.',
          tone: _warning,
        ),
        const SizedBox(height: 18),
        _choiceCard(
          title: 'Agent',
          subtitle: 'Nouvelle recette, validation locale, historique et parametres.',
          icon: Icons.badge_rounded,
          tone: _success,
          onTap: () => setState(() => _role = _RevenueRole.agent),
        ),
        const SizedBox(height: 14),
        _choiceCard(
          title: 'Administration',
          subtitle: 'Dashboard, transactions, rapports et gestion complete des agents.',
          icon: Icons.dashboard_customize_rounded,
          tone: _accent,
          onTap: () => setState(() => _role = _RevenueRole.admin),
        ),
      ],
    );
  }

  Widget _buildAgentLogin() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _hero(
          title: 'Connexion Agent',
          subtitle:
              'Identifiant, mot de passe et option biometrie apres une premiere connexion reussie.',
          colors: const [Color(0xFF16A34A), Color(0xFF0F7A38)],
          icon: Icons.shield_moon_rounded,
        ),
        const SizedBox(height: 18),
        _panel(
          Form(
            key: _agentLoginKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Acces terrain',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 6),
                Text(
                  'Verification de l identifiant et du mot de passe dans la base de donnees.',
                  style: TextStyle(color: _sub, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                _field(
                  label: 'Identifiant',
                  controller: _agentIdentifierCtrl,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Identifiant requis' : null,
                ),
                const SizedBox(height: 12),
                _field(
                  label: 'Mot de passe',
                  controller: _agentPasswordCtrl,
                  obscure: true,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Mot de passe requis' : null,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleAgentLogin,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Se connecter'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ),
                if (_biometricReady) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _handleBiometricLogin,
                      icon: const Icon(Icons.fingerprint_rounded),
                      label: const Text('Connexion biometrie'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _infoBox(
          icon: Icons.info_outline_rounded,
          text:
              'Un agent peut etre cree depuis l espace administration. La biometrie se memorise apres une connexion classique.',
          tone: _accent,
        ),
      ],
    );
  }

  Widget _buildAdminLogin() {
    final fallbackAdmin = _admins.isEmpty ? null : _admins.first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _hero(
          title: 'Connexion Administration',
          subtitle: 'Acces securise au dashboard central et aux fonctions de supervision.',
          colors: const [Color(0xFF0B5FFF), Color(0xFF17306B)],
          icon: Icons.admin_panel_settings_rounded,
        ),
        const SizedBox(height: 18),
        _panel(
          Form(
            key: _adminLoginKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Acces securise',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const SizedBox(height: 16),
                _field(
                  label: 'Identifiant admin',
                  controller: _adminLoginCtrl,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Identifiant requis' : null,
                ),
                const SizedBox(height: 12),
                _field(
                  label: 'Mot de passe',
                  controller: _adminPasswordCtrl,
                  obscure: true,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Mot de passe requis' : null,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _handleAdminLogin,
                    icon: const Icon(Icons.login_rounded),
                    label: const Text('Se connecter'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (fallbackAdmin != null) ...[
          const SizedBox(height: 16),
          _infoBox(
            icon: Icons.key_rounded,
            text:
                'Compte local de demarrage: ${fallbackAdmin.login} / ${fallbackAdmin.password}. Pense a le remplacer par tes vrais admins.',
            tone: _warning,
          ),
        ],
      ],
    );
  }

  Widget _buildAgentWorkspace() {
    final agent = _currentAgent!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _headerCard(
          title: agent.fullName,
          subtitle: '${agent.identifier} / ${agent.commune}',
          badge: agent.enabled ? 'ACTIF' : 'INACTIF',
          tone: agent.enabled ? _success : _warning,
          trailing: '${_pendingTransactions.length} en attente',
          icon: Icons.badge_rounded,
        ),
        const SizedBox(height: 18),
        _navBar<_AgentView>(
          current: _agentView,
          selectedColor: _success,
          items: const [
            (_AgentView.menu, 'Menu'),
            (_AgentView.newTransaction, 'Nouvelle'),
            (_AgentView.pending, 'Validation'),
            (_AgentView.history, 'Historique'),
            (_AgentView.settings, 'Parametres'),
          ],
          onTap: (value) => setState(() => _agentView = value),
        ),
        const SizedBox(height: 18),
        if (_agentView == _AgentView.menu) _buildAgentMenu(),
        if (_agentView == _AgentView.newTransaction) _buildAgentTransactionForm(),
        if (_agentView == _AgentView.pending) _buildPendingTransactions(),
        if (_agentView == _AgentView.history) _buildAgentHistory(),
        if (_agentView == _AgentView.settings) _buildAgentSettings(),
      ],
    );
  }

  Widget _buildAgentMenu() {
    final today = DateTime.now();
    final totalDay = _agentTransactions
        .where((tx) =>
            tx.date.year == today.year &&
            tx.date.month == today.month &&
            tx.date.day == today.day)
        .fold<double>(0, (sum, tx) => sum + tx.amount);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _metricCard('Total du jour', _currency.format(totalDay), _success)),
            const SizedBox(width: 12),
            Expanded(child: _metricCard('Locales', '${_pendingTransactions.length}', _warning)),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _actionCard(
              title: 'Nouvelle Recette',
              subtitle: 'Montant, type, contribuable, numero et horodatage auto.',
              icon: Icons.add_circle_outline_rounded,
              tone: _success,
              onTap: () => setState(() => _agentView = _AgentView.newTransaction),
            ),
            _actionCard(
              title: 'Validation locale',
              subtitle: 'Transactions non envoyees ou en attente.',
              icon: Icons.cloud_sync_outlined,
              tone: _warning,
              onTap: () => setState(() => _agentView = _AgentView.pending),
            ),
            _actionCard(
              title: 'Historique',
              subtitle: 'Filtres par date, type et statut.',
              icon: Icons.history_rounded,
              tone: _accent,
              onTap: () => setState(() => _agentView = _AgentView.history),
            ),
            _actionCard(
              title: 'Parametres',
              subtitle: 'Synchronisation, biometrie et compte agent.',
              icon: Icons.settings_outlined,
              tone: const Color(0xFF7C3AED),
              onTap: () => setState(() => _agentView = _AgentView.settings),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAgentTransactionForm() {
    return _panel(
      Form(
        key: _transactionKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _editingTransaction == null ? 'Nouvelle Recette' : 'Modification locale',
              style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              'Numero et date automatiques. Le statut initial est EN_ATTENTE.',
              style: TextStyle(color: _sub, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _readonlyTile('Numero', _currentTransactionNumber)),
                const SizedBox(width: 12),
                Expanded(
                  child: _readonlyTile(
                    'Date + heure',
                    DateFormat('dd/MM/yyyy HH:mm').format(_currentTransactionDate),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _field(
              label: 'Montant',
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => v == null || v.trim().isEmpty ? 'Montant requis' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedTransactionType,
              decoration: _inputDecoration('Type'),
              items: const [
                DropdownMenuItem(value: 'Taxe', child: Text('Taxe')),
                DropdownMenuItem(value: 'Redevance', child: Text('Redevance')),
                DropdownMenuItem(value: 'Autre', child: Text('Autre')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedTransactionType = value);
              },
            ),
            const SizedBox(height: 12),
            _field(
              label: 'Nom du contribuable',
              controller: _taxpayerCtrl,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Nom du contribuable requis' : null,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitTransaction,
                icon: Icon(_editingTransaction == null ? Icons.verified_outlined : Icons.save_outlined),
                label: Text(_editingTransaction == null ? 'Valider' : 'Mettre a jour'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _success,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _infoBox(
              icon: Icons.wifi_tethering_error_rounded,
              text:
                  'Si le reseau echoue, la recette est gardee localement et remonte dans Validation locale.',
              tone: _warning,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingTransactions() {
    if (_pendingTransactions.isEmpty) {
      return _emptyCard('Aucune transaction locale', 'Les recettes hors ligne apparaitront ici.');
    }
    return Column(
      children: [
        _panel(
          Row(
            children: [
              Expanded(
                child: Text(
                  'Transactions en attente de synchronisation',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w800),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _syncPendingTransactions,
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Synchroniser'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _warning,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ..._pendingTransactions.map((tx) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _transactionCard(
                tx,
                _warning,
                actions: [
                  TextButton.icon(
                    onPressed: () => _editPendingTransaction(tx),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Modifier'),
                  ),
                  TextButton.icon(
                    onPressed: () => _confirmPendingTransaction(tx),
                    icon: const Icon(Icons.cloud_upload_outlined),
                    label: const Text('Confirmer'),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildAgentHistory() {
    return Column(
      children: [
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Historique',
                style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickHistoryDate,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                      _historyDate == null
                          ? 'Date'
                          : DateFormat('dd/MM/yyyy').format(_historyDate!),
                    ),
                  ),
                  if (_historyDate != null)
                    OutlinedButton(
                      onPressed: () => setState(() => _historyDate = null),
                      child: const Text('Effacer'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _historyType,
                      decoration: _inputDecoration('Type'),
                      items: const [
                        DropdownMenuItem(value: 'TOUT', child: Text('Tous')),
                        DropdownMenuItem(value: 'Taxe', child: Text('Taxe')),
                        DropdownMenuItem(value: 'Redevance', child: Text('Redevance')),
                        DropdownMenuItem(value: 'Autre', child: Text('Autre')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _historyType = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _historyStatus,
                      decoration: _inputDecoration('Statut'),
                      items: const [
                        DropdownMenuItem(value: 'TOUT', child: Text('Tous')),
                        DropdownMenuItem(value: 'EN_ATTENTE', child: Text('En attente')),
                        DropdownMenuItem(value: 'VALIDE', child: Text('Valide')),
                        DropdownMenuItem(value: 'REJETE', child: Text('Rejete')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _historyStatus = value);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_filteredHistory.isEmpty)
          _emptyCard('Aucune recette', 'Ajuste les filtres pour afficher des encaissements.')
        else
          ..._filteredHistory.map(
            (tx) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _transactionCard(tx, _statusColor(tx.status)),
            ),
          ),
      ],
    );
  }

  Widget _buildAgentSettings() {
    final agent = _currentAgent!;
    return Column(
      children: [
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Parametres', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18)),
              const SizedBox(height: 12),
              _detailLine('Nom', agent.fullName),
              _detailLine('Identifiant', agent.identifier),
              _detailLine('Telephone', agent.phone),
              _detailLine('Commune', agent.commune),
              _detailLine('Genre', agent.gender),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _actionCard(
          title: 'Synchroniser maintenant',
          subtitle: 'Tente d envoyer toutes les recettes locales.',
          icon: Icons.sync_rounded,
          tone: _warning,
          onTap: _syncPendingTransactions,
        ),
        const SizedBox(height: 12),
        _actionCard(
          title: 'Memoriser pour biometrie',
          subtitle: 'Active l acces rapide par empreinte ou biometrie.',
          icon: Icons.fingerprint_rounded,
          tone: _accent,
          onTap: () async {
            await _repository.saveBiometricAgent(agent);
            if (!mounted) return;
            setState(() => _biometricReady = true);
            _showSnack('Compte memorise pour la biometrie.', color: _success);
          },
        ),
      ],
    );
  }

  Widget _buildAdminWorkspace() {
    final admin = _currentAdmin!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        _headerCard(
          title: admin.name,
          subtitle: '${admin.role} / ${admin.login}',
          badge: admin.isSuperAdmin ? 'SUPER ADMIN' : 'ADMIN',
          tone: admin.isSuperAdmin ? _warning : _accent,
          trailing: '${_adminTransactions.length} transactions',
          icon: Icons.admin_panel_settings_rounded,
        ),
        const SizedBox(height: 18),
        _navBar<_AdminView>(
          current: _adminView,
          selectedColor: _accent,
          items: const [
            (_AdminView.dashboard, 'Dashboard'),
            (_AdminView.transactions, 'Transactions'),
            (_AdminView.reports, 'Rapports'),
            (_AdminView.agents, 'Agents'),
          ],
          onTap: (value) => setState(() => _adminView = value),
        ),
        const SizedBox(height: 18),
        if (_adminView == _AdminView.dashboard) _buildDashboard(),
        if (_adminView == _AdminView.transactions) _buildAdminTransactions(),
        if (_adminView == _AdminView.reports) _buildReports(),
        if (_adminView == _AdminView.agents) _buildAgentsManagement(),
      ],
    );
  }

  Widget _buildDashboard() {
    final totalAgents = _agents.length;
    final activeAgents = _agents.where((agent) => agent.enabled).length;
    final totalValidated = _adminTransactions
        .where((tx) => tx.status == 'VALIDE')
        .fold<double>(0, (sum, tx) => sum + tx.amount);
    final totalSubmitted =
        _adminTransactions.fold<double>(0, (sum, tx) => sum + tx.amount);
    final gap = totalSubmitted - totalValidated;
    final pending = _adminTransactions.where((tx) => tx.status == 'EN_ATTENTE').length;
    final anomalies = _adminTransactions.where((tx) => tx.status == 'REJETE').length;

    final byCommune = <String, double>{};
    final byType = <String, double>{};
    for (final tx in _adminTransactions) {
      byCommune.update(tx.commune, (v) => v + tx.amount, ifAbsent: () => tx.amount);
      byType.update(tx.type, (v) => v + tx.amount, ifAbsent: () => tx.amount);
    }
    final communePerformance = _buildCommunePerformance(_adminTransactions);

    return Column(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _dashboardCard('Total encaisse', _currency.format(totalValidated), 'Transactions validees', _success),
            _dashboardCard('Ecart', _currency.format(gap), 'Soumis - valides', _warning),
            _dashboardCard('En attente', '$pending', 'Transactions a traiter', _accent),
            _dashboardCard('Anomalies', '$anomalies', 'Transactions rejetees', _danger),
            _dashboardCard('Total agents', '$totalAgents', '$activeAgents agent(s) actif(s)', const Color(0xFF7C3AED)),
          ],
        ),
        const SizedBox(height: 16),
        _barSection('Recettes par commune', byCommune, _accent),
        const SizedBox(height: 16),
        _communePerformanceSection(communePerformance),
        const SizedBox(height: 16),
        _barSection('Recettes par type', byType, _success),
      ],
    );
  }

  Widget _buildAdminTransactions() {
    return Column(
      children: [
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gestion des transactions',
                style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _adminStatus,
                decoration: _inputDecoration('Filtre de statut'),
                items: const [
                  DropdownMenuItem(value: 'TOUT', child: Text('Tous')),
                  DropdownMenuItem(value: 'EN_ATTENTE', child: Text('En attente')),
                  DropdownMenuItem(value: 'VALIDE', child: Text('Valide')),
                  DropdownMenuItem(value: 'REJETE', child: Text('Rejete')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _adminStatus = value);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_filteredAdminTransactions.isEmpty)
          _emptyCard('Aucune transaction', 'Les recettes remontees apparaitront ici.')
        else
          ..._filteredAdminTransactions.map(
            (tx) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _transactionCard(
                tx,
                _statusColor(tx.status),
                onTap: () => _openTransactionSheet(tx),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildReports() {
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rapports', style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            'Rapports journaliers et mensuels, avec points d accroche PDF et Excel.',
            style: TextStyle(color: _sub, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _actionCard(
                title: 'Rapport journalier',
                subtitle: 'Synthese des recettes du jour.',
                icon: Icons.today_outlined,
                tone: _accent,
                onTap: () => _showReport('journalier'),
              ),
              _actionCard(
                title: 'Rapport mensuel',
                subtitle: 'Vue consolidee du mois en cours.',
                icon: Icons.date_range_outlined,
                tone: _success,
                onTap: () => _showReport('mensuel'),
              ),
              _actionCard(
                title: 'Export PDF',
                subtitle: 'Genere et partage un rapport journalier ou mensuel en PDF.',
                icon: Icons.picture_as_pdf_outlined,
                tone: _warning,
                onTap: _showPdfExportOptions,
              ),
              _actionCard(
                title: 'Export Excel',
                subtitle: 'Point de branchement du futur export tabulaire.',
                icon: Icons.table_chart_outlined,
                tone: const Color(0xFF0D8C60),
                onTap: () => _showSnack('Bouton Excel en place, export a raccorder ensuite.', color: _warning),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAgentsManagement() {
    return Column(
      children: [
        _panel(
          Form(
            key: _agentFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _editingAgent == null ? 'Creation agent' : 'Modification agent',
                        style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18),
                      ),
                    ),
                    if (_editingAgent != null)
                      TextButton(onPressed: _resetAgentForm, child: const Text('Annuler')),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white10
                            : const Color(0xFFF2F5FA),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _border),
                      ),
                      child: _agentPhotoPreview(),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Photo', style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: _pickAgentPhoto,
                            icon: const Icon(Icons.photo_camera_back_outlined),
                            label: const Text('Choisir'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _field(
                  label: 'Nom complet',
                  controller: _agentNameCtrl,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Nom requis' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _selectedAgentGender,
                  decoration: _inputDecoration('Genre'),
                  items: const [
                    DropdownMenuItem(value: 'Masculin', child: Text('Masculin')),
                    DropdownMenuItem(value: 'Feminin', child: Text('Feminin')),
                    DropdownMenuItem(value: 'Autre', child: Text('Autre')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedAgentGender = value);
                  },
                ),
                const SizedBox(height: 12),
                _field(
                  label: 'Numero telephone',
                  controller: _agentPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Numero requis' : null,
                ),
                const SizedBox(height: 12),
                _field(
                  label: 'Commune d affectation',
                  controller: _agentCommuneCtrl,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Commune requise' : null,
                ),
                const SizedBox(height: 12),
                _infoBox(
                  icon: Icons.vpn_key_outlined,
                  text: _editingAgent == null
                      ? 'A la creation: identifiant AGT-00045 et mot de passe temporaire generes automatiquement.'
                      : 'Identifiant: ${_editingAgent!.identifier} / Mot de passe temporaire: ${_editingAgent!.password}',
                  tone: _accent,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _submitAgentForm,
                    icon: Icon(_editingAgent == null ? Icons.person_add_alt_1 : Icons.save_outlined),
                    label: Text(_editingAgent == null ? 'Creer' : 'Modifier'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_agents.isEmpty)
          _emptyCard('Aucun agent', 'Les agents crees apparaitront ici.')
        else
          ..._agents.map((agent) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _agentCard(agent),
              )),
        const SizedBox(height: 12),
        if (_isSuperAdmin) _buildAdminsManagement(),
        const SizedBox(height: 12),
        _buildOwnPasswordPanel(),
      ],
    );
  }

  Widget _agentPhotoPreview() {
    final photoUrl = _editingAgent?.photoUrl;
    if (_agentPhotoBytes != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.memory(_agentPhotoBytes!, fit: BoxFit.cover),
      );
    }
    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.network(
          photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(Icons.person_outline_rounded, color: _sub),
        ),
      );
    }
    return Icon(Icons.person_outline_rounded, color: _sub);
  }

  Widget _buildAdminsManagement() {
    return Column(
      children: [
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gestion des admins',
                style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 6),
              Text(
                'Le super admin peut ajouter des admins, leur attribuer un role et definir leurs acces.',
                style: TextStyle(color: _sub, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              _field(label: 'Nom complet', controller: _adminNameCtrl),
              const SizedBox(height: 12),
              _field(label: 'Role', controller: _adminRoleCtrl),
              const SizedBox(height: 12),
              _field(label: 'Login admin', controller: _newAdminLoginCtrl),
              const SizedBox(height: 12),
              _field(
                label: 'Mot de passe temporaire',
                controller: _newAdminPasswordCtrl,
                obscure: true,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _newAdminIsSuperAdmin,
                onChanged: (value) => setState(() => _newAdminIsSuperAdmin = value),
                title: Text(
                  'Accorder le niveau super admin',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'Active la creation d admins et la supervision complete.',
                  style: TextStyle(color: _sub, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitAdminForm,
                  icon: const Icon(Icons.admin_panel_settings_rounded),
                  label: const Text('Ajouter cet admin'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_admins.isEmpty)
          _emptyCard('Aucun admin', 'Les comptes administratifs apparaitront ici.')
        else
          ..._admins.map(
            (admin) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _adminCard(admin),
            ),
          ),
      ],
    );
  }

  Widget _buildOwnPasswordPanel() {
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mon mot de passe',
            style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            _isSuperAdmin
                ? 'Le super admin peut modifier son mot de passe directement ici.'
                : 'Change ton mot de passe d administration.',
            style: TextStyle(color: _sub, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _field(
            label: 'Mot de passe actuel',
            controller: _currentAdminPasswordCtrl,
            obscure: true,
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Nouveau mot de passe',
            controller: _newOwnPasswordCtrl,
            obscure: true,
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Confirmer le nouveau mot de passe',
            controller: _confirmOwnPasswordCtrl,
            obscure: true,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _changeOwnAdminPassword,
              icon: const Icon(Icons.lock_reset_rounded),
              label: const Text('Mettre a jour mon mot de passe'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _success,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTransactionSheet(_RevenueTransaction tx) async {
    final commentCtrl = TextEditingController(text: tx.comment);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _border),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 56,
                        height: 5,
                        decoration: BoxDecoration(
                          color: _border,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(tx.id, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18)),
                    const SizedBox(height: 6),
                    Text('${tx.taxpayerName} / ${tx.type}', style: TextStyle(color: _sub, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 16),
                    _detailLine('Montant', _currency.format(tx.amount)),
                    _detailLine('Date', DateFormat('dd/MM/yyyy HH:mm').format(tx.date)),
                    _detailLine('Agent', tx.agentName),
                    _detailLine('Commune', tx.commune),
                    _detailLine('Statut', tx.status),
                    if (tx.localOnly) ...[
                      const SizedBox(height: 8),
                      _infoBox(
                        icon: Icons.cloud_off_rounded,
                        text: 'Cette transaction est encore locale. Synchronise-la cote agent avant validation admin.',
                        tone: _warning,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _field(
                      label: 'Commentaire',
                      controller: commentCtrl,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              if (tx.localOnly) {
                                _showSnack('Synchronise d abord la transaction.', color: _warning);
                                return;
                              }
                              await _repository.updateTransactionStatus(
                                tx.id,
                                status: 'REJETE',
                                comment: commentCtrl.text.trim(),
                              );
                              if (!mounted) return;
                              Navigator.pop(context);
                              await _refreshAdminData();
                              _showSnack('Transaction rejetee.', color: _danger);
                            },
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Rejeter'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _danger,
                              side: BorderSide(color: _danger.withOpacity(0.25)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              if (tx.localOnly) {
                                _showSnack('Synchronise d abord la transaction.', color: _warning);
                                return;
                              }
                              await _repository.updateTransactionStatus(
                                tx.id,
                                status: 'VALIDE',
                                comment: commentCtrl.text.trim(),
                              );
                              if (!mounted) return;
                              Navigator.pop(context);
                              await _refreshAdminData();
                              _showSnack('Transaction validee.', color: _success);
                            },
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Valider'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _success,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    commentCtrl.dispose();
  }

  Widget _hero({
    required String title,
    required String subtitle,
    required List<Color> colors,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: colors.first.withOpacity(0.24), blurRadius: 24, offset: const Offset(0, 14))],
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.22)),
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22)),
                const SizedBox(height: 6),
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(Widget child) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 12))],
      ),
      child: child,
    );
  }

  Widget _infoBox({required IconData icon, required String text, required Color tone}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withOpacity(0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: _text, fontWeight: FontWeight.w700, height: 1.35))),
        ],
      ),
    );
  }

  Widget _choiceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color tone,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: _panel(
        Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: tone.withOpacity(0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: tone),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18)),
                  const SizedBox(height: 5),
                  Text(subtitle, style: TextStyle(color: _sub, fontWeight: FontWeight.w600, height: 1.35)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: _sub),
          ],
        ),
      ),
    );
  }

  Widget _headerCard({
    required String title,
    required String subtitle,
    required String badge,
    required Color tone,
    required String trailing,
    required IconData icon,
  }) {
    return _panel(
      Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: tone.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: tone),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: _sub, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: tone.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
                  child: Text(badge, style: TextStyle(color: tone, fontWeight: FontWeight.w900, fontSize: 11)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(trailing, style: TextStyle(color: _sub, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _navBar<T>({
    required T current,
    required List<(T, String)> items,
    required ValueChanged<T> onTap,
    required Color selectedColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: items.map((item) {
          final selected = item.$1 == current;
          return GestureDetector(
            onTap: () => onTap(item.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? selectedColor : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                item.$2,
                style: TextStyle(
                  color: selected ? Colors.white : _text,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _metricCard(String label, String value, Color tone) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: _sub, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 22)),
          const SizedBox(height: 8),
          Container(width: 42, height: 4, decoration: BoxDecoration(color: tone, borderRadius: BorderRadius.circular(999))),
        ],
      ),
    );
  }

  Widget _actionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color tone,
    required VoidCallback onTap,
  }) {
    final width = MediaQuery.of(context).size.width > 540
        ? (MediaQuery.of(context).size.width - 60) / 2
        : double.infinity;
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: _border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: tone.withOpacity(0.12), borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: tone),
              ),
              const SizedBox(height: 14),
              Text(title, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 16)),
              const SizedBox(height: 6),
              Text(subtitle, style: TextStyle(color: _sub, fontWeight: FontWeight.w600, height: 1.35)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _readonlyTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: _sub, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: _text, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? Function(String?)? validator,
    bool obscure = false,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscure,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(color: _text, fontWeight: FontWeight.w700),
      decoration: _inputDecoration(label),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _sub, fontWeight: FontWeight.w700),
      filled: true,
      fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF7F9FC),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _accent, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.2),
      ),
    );
  }

  Widget _transactionCard(
    _RevenueTransaction tx,
    Color tone, {
    List<Widget> actions = const [],
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tx.id, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 16)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: tone.withOpacity(0.12), borderRadius: BorderRadius.circular(999)),
                  child: Text(tx.status, style: TextStyle(color: tone, fontWeight: FontWeight.w900, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('${tx.taxpayerName} / ${tx.type}', style: TextStyle(color: _sub, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _miniData('Montant', _currency.format(tx.amount))),
                Expanded(child: _miniData('Date', DateFormat('dd/MM HH:mm').format(tx.date))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _miniData('Agent', tx.agentName)),
                Expanded(child: _miniData('Commune', tx.commune)),
              ],
            ),
            if (tx.localOnly) ...[
              const SizedBox(height: 10),
              Text('Mode local - non synchronisee', style: TextStyle(color: tone, fontWeight: FontWeight.w800)),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: actions),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniData(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: _sub, fontWeight: FontWeight.w700, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _emptyCard(String title, String subtitle) {
    return _panel(
      Column(
        children: [
          Icon(Icons.inbox_outlined, color: _sub, size: 40),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 6),
          Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: _sub, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _dashboardCard(String title, String value, String subtitle, Color tone) {
    final width = MediaQuery.of(context).size.width > 540
        ? (MediaQuery.of(context).size.width - 60) / 2
        : double.infinity;
    return SizedBox(width: width, child: _metricCard(title, value, tone));
  }

  Widget _barSection(String title, Map<String, double> data, Color tone) {
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 12),
          if (data.isEmpty)
            Text('Pas encore de donnees disponibles.', style: TextStyle(color: _sub, fontWeight: FontWeight.w600))
          else
            ...data.entries.map((entry) {
              final maxValue = data.values.reduce(max);
              final ratio = maxValue <= 0 ? 0.0 : (entry.value / maxValue).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(entry.key, style: TextStyle(color: _text, fontWeight: FontWeight.w800))),
                        Text(_currency.format(entry.value), style: TextStyle(color: _sub, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        minHeight: 12,
                        value: ratio,
                        color: tone,
                        backgroundColor: tone.withOpacity(0.12),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _agentCard(_RevenueAgent agent) {
    Uint8List? photo;
    if (agent.photoBase64 != null && agent.photoBase64!.isNotEmpty) {
      try {
        photo = base64Decode(agent.photoBase64!);
      } catch (_) {
        photo = null;
      }
    }
    return _panel(
      Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F5FA),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: photo == null
                    ? (agent.photoUrl != null && agent.photoUrl!.trim().isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.network(
                              agent.photoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Icon(Icons.person_outline_rounded, color: _sub),
                            ),
                          )
                        : Icon(Icons.person_outline_rounded, color: _sub))
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.memory(photo, fit: BoxFit.cover),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(agent.fullName, style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('${agent.identifier} / ${agent.commune}', style: TextStyle(color: _sub, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(agent.phone, style: TextStyle(color: _sub, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (agent.enabled ? _success : _warning).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  agent.enabled ? 'ACTIF' : 'DESACTIVE',
                  style: TextStyle(color: agent.enabled ? _success : _warning, fontWeight: FontWeight.w900, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _prepareAgentEdit(agent),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _toggleAgentState(agent),
                  icon: Icon(agent.enabled ? Icons.block_outlined : Icons.check_circle_outline),
                  label: Text(agent.enabled ? 'Desactiver' : 'Reactiver'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _adminCard(_RevenueAdmin admin) {
    return _panel(
      Column(
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: (admin.isSuperAdmin ? _accent : _warning).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  admin.isSuperAdmin
                      ? Icons.security_rounded
                      : Icons.admin_panel_settings_rounded,
                  color: admin.isSuperAdmin ? _accent : _warning,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      admin.name,
                      style: TextStyle(color: _text, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${admin.login} / ${admin.role}',
                      style: TextStyle(color: _sub, fontWeight: FontWeight.w600),
                    ),
                    if ((admin.createdByAdminId ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Cree par: ${admin.createdByAdminId}',
                        style: TextStyle(color: _sub, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (admin.isSuperAdmin ? _accent : _success).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  admin.isSuperAdmin ? 'SUPER ADMIN' : 'ADMIN',
                  style: TextStyle(
                    color: admin.isSuperAdmin ? _accent : _success,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: TextStyle(color: _sub, fontWeight: FontWeight.w700))),
          Expanded(child: Text(value, style: TextStyle(color: _text, fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  Future<void> _showReport(String period) async {
    final items = _reportTransactions(period);
    final total = items.fold<double>(0, (sum, tx) => sum + tx.amount);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Rapport $period'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transactions: ${items.length}'),
            Text('Montant: ${_currency.format(total)}'),
            Text('Validees: ${items.where((e) => e.status == 'VALIDE').length}'),
            Text('En attente: ${items.where((e) => e.status == 'EN_ATTENTE').length}'),
            Text('Rejetees: ${items.where((e) => e.status == 'REJETE').length}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer')),
        ],
      ),
    );
  }

  List<_RevenueTransaction> _reportTransactions(String period) {
    final now = DateTime.now();
    return _adminTransactions.where((tx) {
      if (period == 'journalier') {
        return tx.date.year == now.year &&
            tx.date.month == now.month &&
            tx.date.day == now.day;
      }
      return tx.date.year == now.year && tx.date.month == now.month;
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  List<_CommunePerformance> _buildCommunePerformance(
    List<_RevenueTransaction> transactions,
  ) {
    final totals = <String, _CommunePerformance>{};
    for (final tx in transactions) {
      final key =
          tx.commune.trim().isEmpty ? 'Commune inconnue' : tx.commune.trim();
      final current = totals[key] ??
          _CommunePerformance(
            commune: key,
            totalAmount: 0,
            validatedAmount: 0,
            transactionCount: 0,
            validatedCount: 0,
            agentCount: _agents
                .where(
                  (agent) => agent.commune.trim().toLowerCase() == key.toLowerCase(),
                )
                .length,
          );
      totals[key] = current.copyWith(
        totalAmount: current.totalAmount + tx.amount,
        validatedAmount: current.validatedAmount +
            (tx.status == 'VALIDE' ? tx.amount : 0),
        transactionCount: current.transactionCount + 1,
        validatedCount: current.validatedCount +
            (tx.status == 'VALIDE' ? 1 : 0),
      );
    }

    final list = totals.values.toList()
      ..sort((a, b) {
        final byValidated = b.validatedAmount.compareTo(a.validatedAmount);
        if (byValidated != 0) return byValidated;
        final byRate = b.performanceRate.compareTo(a.performanceRate);
        if (byRate != 0) return byRate;
        return a.commune.toLowerCase().compareTo(b.commune.toLowerCase());
      });
    return list;
  }

  Widget _communePerformanceSection(List<_CommunePerformance> items) {
    return _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Classement des communes par performance',
            style: TextStyle(
              color: _text,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Classement base sur le montant valide, avec taux de validation et nombre d agents.',
            style: TextStyle(color: _sub, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            Text(
              'Aucune performance disponible pour le moment.',
              style: TextStyle(color: _sub, fontWeight: FontWeight.w600),
            )
          else
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _accent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: _accent,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.commune,
                              style: TextStyle(
                                color: _text,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item.agentCount} agent(s) / ${item.transactionCount} transaction(s)',
                              style: TextStyle(
                                color: _sub,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _currency.format(item.validatedAmount),
                            style: TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.performanceRate.toStringAsFixed(0)}% valide',
                            style: TextStyle(
                              color: _sub,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _showPdfExportOptions() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Exporter en PDF',
                    style: TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Choisis le type de rapport a generer.',
                    style: TextStyle(color: _sub, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.today_outlined),
                    title: const Text('Rapport journalier'),
                    onTap: () async {
                      Navigator.pop(context);
                      await _exportReportPdf('journalier');
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.date_range_outlined),
                    title: const Text('Rapport mensuel'),
                    onTap: () async {
                      Navigator.pop(context);
                      await _exportReportPdf('mensuel');
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportReportPdf(String period) async {
    final items = _reportTransactions(period);
    setState(() => _busy = true);
    try {
      final bytes = _buildReportPdfBytes(period: period, transactions: items);
      final label = period == 'journalier' ? 'journalier' : 'mensuel';
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final fileName = 'rapport_recettes_${label}_$timestamp.pdf';
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: fileName,
          ),
        ],
        subject: 'Rapport des recettes $label',
        text: 'Rapport des recettes $label',
      );
    } catch (e) {
      _showSnack('Erreur export PDF: $e', color: _danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Uint8List _buildReportPdfBytes({
    required String period,
    required List<_RevenueTransaction> transactions,
  }) {
    final now = DateTime.now();
    final total = transactions.fold<double>(0, (sum, tx) => sum + tx.amount);
    final validated = transactions
        .where((tx) => tx.status == 'VALIDE')
        .fold<double>(0, (sum, tx) => sum + tx.amount);
    final pending = transactions.where((tx) => tx.status == 'EN_ATTENTE').length;
    final rejected = transactions.where((tx) => tx.status == 'REJETE').length;
    final communes = _buildCommunePerformance(transactions);

    final document = PdfDocument();
    final page = document.pages.add();
    final size = page.getClientSize();
    const margin = 28.0;
    final titleFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      18,
      style: PdfFontStyle.bold,
    );
    final sectionFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      12,
      style: PdfFontStyle.bold,
    );
    final textFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
    final boldFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      10,
      style: PdfFontStyle.bold,
    );

    final g = page.graphics;
    g.drawString(
      'RAPPORT DES RECETTES - ${period.toUpperCase()}',
      titleFont,
      bounds: Rect.fromLTWH(margin, margin, size.width - margin * 2, 26),
    );

    final dateLabel = DateFormat('dd/MM/yyyy HH:mm').format(now);
    double y = margin + 30;
    g.drawString(
      'Genere le: $dateLabel',
      textFont,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 14),
    );
    y += 20;

    final summaryGrid = PdfGrid();
    summaryGrid.columns.add(count: 2);
    summaryGrid.style = PdfGridStyle(
      font: textFont,
      cellPadding: PdfPaddings(left: 6, right: 6, top: 6, bottom: 6),
    );

    void addSummary(String label, String value) {
      final row = summaryGrid.rows.add();
      row.cells[0].value = label;
      row.cells[1].value = value;
      row.cells[0].style = PdfGridCellStyle(font: boldFont);
    }

    addSummary('Transactions', '${transactions.length}');
    addSummary('Montant total', _currency.format(total));
    addSummary('Montant valide', _currency.format(validated));
    addSummary('En attente', '$pending');
    addSummary('Rejetees', '$rejected');
    addSummary('Total agents', '${_agents.length}');

    final summaryResult = summaryGrid.draw(
      page: page,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 0),
    );
    y = (summaryResult?.bounds.bottom ?? y) + 16;

    g.drawString(
      'Classement des communes',
      sectionFont,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 18),
    );
    y += 20;

    final communeGrid = PdfGrid();
    communeGrid.columns.add(count: 5);
    communeGrid.style = PdfGridStyle(
      font: textFont,
      cellPadding: PdfPaddings(left: 5, right: 5, top: 5, bottom: 5),
    );
    final communeHeader = communeGrid.headers.add(1)[0];
    communeHeader.cells[0].value = 'Rang';
    communeHeader.cells[1].value = 'Commune';
    communeHeader.cells[2].value = 'Agents';
    communeHeader.cells[3].value = 'Valide';
    communeHeader.cells[4].value = 'Performance';
    communeHeader.style = PdfGridRowStyle(
      backgroundBrush: PdfSolidBrush(PdfColor(245, 245, 245)),
      font: boldFont,
    );

    for (final entry in communes.asMap().entries) {
      final row = communeGrid.rows.add();
      row.cells[0].value = '${entry.key + 1}';
      row.cells[1].value = entry.value.commune;
      row.cells[2].value = '${entry.value.agentCount}';
      row.cells[3].value = _currency.format(entry.value.validatedAmount);
      row.cells[4].value = '${entry.value.performanceRate.toStringAsFixed(0)}%';
    }

    final communeResult = communeGrid.draw(
      page: page,
      bounds: Rect.fromLTWH(margin, y, size.width - margin * 2, 0),
      format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
    );

    final detailPage = communeResult?.page ?? page;
    final detailY = (communeResult?.bounds.bottom ?? y) + 16;
    detailPage.graphics.drawString(
      'Transactions',
      sectionFont,
      bounds: Rect.fromLTWH(margin, detailY, size.width - margin * 2, 18),
    );

    final detailGrid = PdfGrid();
    detailGrid.columns.add(count: 5);
    detailGrid.style = PdfGridStyle(
      font: textFont,
      cellPadding: PdfPaddings(left: 5, right: 5, top: 5, bottom: 5),
    );
    final detailHeader = detailGrid.headers.add(1)[0];
    detailHeader.cells[0].value = 'Numero';
    detailHeader.cells[1].value = 'Contribuable';
    detailHeader.cells[2].value = 'Commune';
    detailHeader.cells[3].value = 'Montant';
    detailHeader.cells[4].value = 'Statut';
    detailHeader.style = PdfGridRowStyle(
      backgroundBrush: PdfSolidBrush(PdfColor(245, 245, 245)),
      font: boldFont,
    );

    for (final tx in transactions) {
      final row = detailGrid.rows.add();
      row.cells[0].value = tx.id;
      row.cells[1].value = tx.taxpayerName;
      row.cells[2].value = tx.commune;
      row.cells[3].value = _currency.format(tx.amount);
      row.cells[4].value = tx.status;
    }

    detailGrid.draw(
      page: detailPage,
      bounds: Rect.fromLTWH(margin, detailY + 20, size.width - margin * 2, 0),
      format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
    );

    final bytes = Uint8List.fromList(document.saveSync());
    document.dispose();
    return bytes;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'VALIDE':
        return _success;
      case 'REJETE':
        return _danger;
      default:
        return _warning;
    }
  }
}

class _CommunePerformance {
  const _CommunePerformance({
    required this.commune,
    required this.totalAmount,
    required this.validatedAmount,
    required this.transactionCount,
    required this.validatedCount,
    required this.agentCount,
  });

  final String commune;
  final double totalAmount;
  final double validatedAmount;
  final int transactionCount;
  final int validatedCount;
  final int agentCount;

  double get performanceRate {
    if (totalAmount <= 0) return 0;
    return (validatedAmount / totalAmount) * 100;
  }

  _CommunePerformance copyWith({
    String? commune,
    double? totalAmount,
    double? validatedAmount,
    int? transactionCount,
    int? validatedCount,
    int? agentCount,
  }) {
    return _CommunePerformance(
      commune: commune ?? this.commune,
      totalAmount: totalAmount ?? this.totalAmount,
      validatedAmount: validatedAmount ?? this.validatedAmount,
      transactionCount: transactionCount ?? this.transactionCount,
      validatedCount: validatedCount ?? this.validatedCount,
      agentCount: agentCount ?? this.agentCount,
    );
  }
}

class _RevenueRepository {
  static const _agentsKey = 'revenue_agents_v1';
  static const _adminsKey = 'revenue_admins_v1';
  static const _transactionsKey = 'revenue_transactions_v1';
  static const _biometricAgentKey = 'revenue_biometric_agent_v1';
  static const _txCounterKey = 'revenue_tx_counter_v1';
  static const _agentsTable = 'revenue_agents';
  static const _adminsTable = 'revenue_admins';
  static const _transactionsTable = 'revenue_transactions';
  static const _agentPhotosBucket = 'profiles';

  Future<SharedPreferences> get _prefs async => SharedPreferences.getInstance();
  SupabaseClient? get _supabase =>
      SupabaseService.isInitialized ? Supabase.instance.client : null;

  Future<void> ensureBootstrapData() async {
    final prefs = await _prefs;
    final admins = _decodeAdmins(prefs.getString(_adminsKey));
    if (admins.any((admin) => admin.isSuperAdmin)) return;
    const bootstrap = _RevenueAdmin(
      id: 'ADM-00001',
      name: 'Super administrateur',
      role: 'SUPER_ADMIN',
      login: 'admin',
      password: 'admin123',
      localOnly: false,
      isSuperAdmin: true,
    );
    final updated = [...admins.where((admin) => admin.id != bootstrap.id), bootstrap];
    await _writeAdmins(updated);
    await _upsertAdminRemote(bootstrap);
  }

  Future<_RevenueAgent?> loginAgent({
    required String identifier,
    required String password,
  }) async {
    final agents = await loadAgents();
    for (final agent in agents) {
      if (agent.identifier == identifier &&
          agent.password == password &&
          agent.enabled) {
        return agent;
      }
    }
    return null;
  }

  Future<_RevenueAdmin?> loginAdmin({
    required String login,
    required String password,
  }) async {
    final admins = await loadAdmins();
    for (final admin in admins) {
      if (admin.login == login && admin.password == password) return admin;
    }
    return null;
  }

  Future<List<_RevenueAdmin>> loadAdmins() async {
    final prefs = await _prefs;
    final merged = <String, _RevenueAdmin>{
      for (final item in _decodeAdmins(prefs.getString(_adminsKey))) item.id: item,
    };
    final remote = await _selectRows(_adminsTable);
    for (final row in remote) {
      final admin = _RevenueAdmin.fromJson(row);
      merged[admin.id] = admin;
    }
    final items = merged.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _writeAdmins(items);
    return items;
  }

  Future<List<_RevenueAgent>> loadAgents() async {
    final prefs = await _prefs;
    final merged = <String, _RevenueAgent>{
      for (final item in _decodeAgents(prefs.getString(_agentsKey))) item.id: item,
    };
    final remote = await _selectRows(_agentsTable);
    for (final row in remote) {
      final remoteAgent = _RevenueAgent.fromJson(row);
      final localAgent = merged[remoteAgent.id];
      merged[remoteAgent.id] = remoteAgent.copyWith(
        photoBase64: localAgent?.photoBase64 ?? remoteAgent.photoBase64,
      );
    }
    final items = merged.values.toList()
      ..sort((a, b) => a.identifier.compareTo(b.identifier));
    await _writeAgents(items);
    return items;
  }

  Future<_RevenueAdmin?> saveAdmin({
    required _RevenueAdmin? existing,
    required String name,
    required String role,
    required String login,
    required String password,
    required bool isSuperAdmin,
    required String createdByAdminId,
  }) async {
    final admins = await loadAdmins();
    final duplicate = admins.any(
      (admin) =>
          admin.login.toLowerCase() == login.toLowerCase() &&
          admin.id != existing?.id,
    );
    if (duplicate) return null;

    final admin = _RevenueAdmin(
      id: existing?.id ?? 'ADM-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      role: role,
      login: login,
      password: password,
      localOnly: false,
      isSuperAdmin: isSuperAdmin,
      createdByAdminId: createdByAdminId,
    );

    final updated = [...admins.where((item) => item.id != admin.id), admin];
    await _writeAdmins(updated);
    await _upsertAdminRemote(admin);
    return admin;
  }

  Future<_RevenueAdmin?> updateAdminPassword({
    required String adminId,
    required String newPassword,
  }) async {
    final admins = await loadAdmins();
    final index = admins.indexWhere((admin) => admin.id == adminId);
    if (index < 0) return null;
    final updated = admins[index].copyWith(password: newPassword);
    final next = [...admins]..[index] = updated;
    await _writeAdmins(next);
    await _upsertAdminRemote(updated);
    return updated;
  }

  Future<_RevenueAgent> saveAgent({
    required _RevenueAgent? existing,
    required String fullName,
    required String gender,
    required String phone,
    required String commune,
    required String? photoBase64,
  }) async {
    final agents = await loadAgents();
    final next = existing == null ? _nextAgentNumber(agents) : null;
    final identifier =
        existing?.identifier ?? 'AGT-${next!.toString().padLeft(5, '0')}';
    String? photoUrl = existing?.photoUrl;
    if (photoBase64 != null &&
        photoBase64.isNotEmpty &&
        photoBase64 != existing?.photoBase64) {
      try {
        photoUrl = await _uploadAgentPhoto(
          base64Decode(photoBase64),
          identifier: identifier,
        );
      } catch (_) {}
    }
    final agent = _RevenueAgent(
      id: existing?.id ?? identifier,
      fullName: fullName,
      gender: gender,
      phone: phone,
      commune: commune,
      identifier: identifier,
      password: existing?.password ?? _generateTempPassword(),
      enabled: existing?.enabled ?? true,
      localOnly: false,
      photoBase64: photoBase64,
      photoUrl: photoUrl,
    );

    final items = [...agents.where((item) => item.id != agent.id), agent];
    await _writeAgents(items);
    await _upsertAgentRemote(agent);
    return agent;
  }

  Future<void> toggleAgentEnabled(_RevenueAgent agent) async {
    final updated = agent.copyWith(enabled: !agent.enabled);
    final agents = await loadAgents();
    final items = [...agents.where((item) => item.id != updated.id), updated];
    await _writeAgents(items);
    await _upsertAgentRemote(updated);
  }

  Future<String> reserveNextTransactionNumber() async {
    final prefs = await _prefs;
    final current = prefs.getInt(_txCounterKey) ?? 0;
    final next = current + 1;
    await prefs.setInt(_txCounterKey, next);
    return 'TRX-${DateTime.now().year}-${next.toString().padLeft(4, '0')}';
  }

  Future<_RevenueTransaction> saveOrQueueTransaction(_RevenueTransaction tx) async {
    if (await _hasNetwork()) {
      try {
        final remote = tx.copyWith(localOnly: false);
        await _upsertTransactionRemote(remote);
        return remote;
      } catch (_) {}
    }
    final items = [...await loadPendingTransactions()];
    items.removeWhere((e) => e.id == tx.id);
    items.add(tx.copyWith(localOnly: true));
    await _writeTransactions(items);
    return tx.copyWith(localOnly: true);
  }

  Future<_RevenueTransaction> updatePendingTransaction(_RevenueTransaction tx) async {
    final items = [...await loadPendingTransactions()];
    items.removeWhere((e) => e.id == tx.id);
    items.add(tx.copyWith(localOnly: true));
    await _writeTransactions(items);
    return tx.copyWith(localOnly: true);
  }

  Future<bool> confirmPendingTransaction(_RevenueTransaction tx) async {
    if (!await _hasNetwork()) return false;
    try {
      final remote = tx.copyWith(localOnly: false);
      await _upsertTransactionRemote(remote);
      final items = [...await loadPendingTransactions()]..removeWhere((e) => e.id == tx.id);
      await _writeTransactions(items);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> syncPendingTransactions({String? agentId}) async {
    final items = [...await loadPendingTransactions()];
    final synced = <String>[];
    for (final tx in items) {
      if (agentId != null && tx.agentId != agentId) continue;
      try {
        await _upsertTransactionRemote(tx.copyWith(localOnly: false));
        synced.add(tx.id);
      } catch (_) {}
    }
    if (synced.isEmpty) return 0;
    items.removeWhere((e) => synced.contains(e.id));
    await _writeTransactions(items);
    return synced.length;
  }

  Future<List<_RevenueTransaction>> loadPendingTransactions({String? agentId}) async {
    final prefs = await _prefs;
    final items = _decodeTransactions(prefs.getString(_transactionsKey));
    final filtered = agentId == null
        ? items
        : items.where((e) => e.agentId == agentId).toList();
    filtered.sort((a, b) => b.date.compareTo(a.date));
    return filtered;
  }

  Future<List<_RevenueTransaction>> loadTransactions({String? agentId}) async {
    final prefs = await _prefs;
    final local = _decodeTransactions(prefs.getString(_transactionsKey));
    final merged = <String, _RevenueTransaction>{};
    for (final tx in local) {
      if (agentId == null || tx.agentId == agentId) merged[tx.id] = tx;
    }
    final remote = await _selectRows(
      _transactionsTable,
      filterColumn: agentId == null ? null : 'agent_id',
      filterValue: agentId,
    );
    for (final row in remote) {
      final tx = _RevenueTransaction.fromJson(row);
      merged[tx.id] = tx;
    }
    final items = merged.values.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return items;
  }

  Future<void> updateTransactionStatus(
    String transactionId, {
    required String status,
    required String comment,
  }) async {
    final supabase = _supabase;
    if (supabase == null) return;
    try {
      await SupabaseService.ensureAuthenticated();
      await supabase.from(_transactionsTable).update({
        'statut': status,
        'commentaire': comment,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', transactionId);
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> _selectRows(
    String table, {
    String? filterColumn,
    dynamic filterValue,
  }) async {
    final supabase = _supabase;
    if (supabase == null) return [];
    try {
      await SupabaseService.ensureAuthenticated();
      dynamic query = supabase.from(table).select();
      if (filterColumn != null && filterValue != null) {
        query = query.eq(filterColumn, filterValue);
      }
      final dynamic rows = await query;
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      return [];
    }
  }

  Future<void> _upsertAdminRemote(_RevenueAdmin admin) async {
    final supabase = _supabase;
    if (supabase == null) return;
    try {
      await SupabaseService.ensureAuthenticated();
      final payload = Map<String, dynamic>.from(admin.toJson())
        ..['local_only'] = false;
      await supabase.from(_adminsTable).upsert(payload);
    } catch (_) {}
  }

  Future<void> _upsertAgentRemote(_RevenueAgent agent) async {
    final supabase = _supabase;
    if (supabase == null) return;
    try {
      await SupabaseService.ensureAuthenticated();
      final payload = Map<String, dynamic>.from(agent.toJson())
        ..remove('photo')
        ..['local_only'] = false;
      await supabase.from(_agentsTable).upsert(payload);
    } catch (_) {}
  }

  Future<void> _upsertTransactionRemote(_RevenueTransaction tx) async {
    final supabase = _supabase;
    if (supabase == null) throw Exception('Supabase non initialise');
    await SupabaseService.ensureAuthenticated();
    final payload = Map<String, dynamic>.from(tx.toJson())
      ..['local_only'] = false;
    await supabase.from(_transactionsTable).upsert(payload);
  }

  Future<String?> _uploadAgentPhoto(
    Uint8List bytes, {
    required String identifier,
  }) async {
    final supabase = _supabase;
    if (supabase == null) return null;
    await SupabaseService.ensureAuthenticated();
    final now = DateTime.now().millisecondsSinceEpoch;
    final path = 'revenue_agents/${identifier}_$now.jpg';
    await supabase.storage.from(_agentPhotosBucket).uploadBinary(
      path,
      bytes,
      fileOptions: const FileOptions(
        upsert: true,
        contentType: 'image/jpeg',
      ),
    );
    return supabase.storage.from(_agentPhotosBucket).getPublicUrl(path);
  }

  Future<void> _writeAdmins(List<_RevenueAdmin> admins) async {
    final prefs = await _prefs;
    await prefs.setString(
      _adminsKey,
      jsonEncode(admins.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _writeAgents(List<_RevenueAgent> agents) async {
    final prefs = await _prefs;
    await prefs.setString(
      _agentsKey,
      jsonEncode(agents.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _writeTransactions(List<_RevenueTransaction> items) async {
    final prefs = await _prefs;
    await prefs.setString(
      _transactionsKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> saveBiometricAgent(_RevenueAgent agent) async {
    final prefs = await _prefs;
    await prefs.setString(_biometricAgentKey, jsonEncode(agent.toJson()));
  }

  Future<_RevenueAgent?> loadBiometricAgent() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_biometricAgentKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return _RevenueAgent.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  List<_RevenueAgent> _decodeAgents(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => _RevenueAgent.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  List<_RevenueAdmin> _decodeAdmins(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => _RevenueAdmin.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  List<_RevenueTransaction> _decodeTransactions(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => _RevenueTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  int _nextAgentNumber(List<_RevenueAgent> agents) {
    var maxNumber = 0;
    for (final agent in agents) {
      final parts = agent.identifier.split('-');
      if (parts.length < 2) continue;
      final parsed = int.tryParse(parts.last) ?? 0;
      if (parsed > maxNumber) maxNumber = parsed;
    }
    return maxNumber + 1;
  }

  String _generateTempPassword() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  Future<bool> _hasNetwork() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (_) {
      return false;
    }
  }
}

class _RevenueAgent {
  const _RevenueAgent({
    required this.id,
    required this.fullName,
    required this.gender,
    required this.phone,
    required this.commune,
    required this.identifier,
    required this.password,
    required this.enabled,
    required this.localOnly,
    this.photoBase64,
    this.photoUrl,
  });

  final String id;
  final String fullName;
  final String gender;
  final String phone;
  final String commune;
  final String identifier;
  final String password;
  final bool enabled;
  final bool localOnly;
  final String? photoBase64;
  final String? photoUrl;

  _RevenueAgent copyWith({
    String? id,
    String? fullName,
    String? gender,
    String? phone,
    String? commune,
    String? identifier,
    String? password,
    bool? enabled,
    bool? localOnly,
    String? photoBase64,
    String? photoUrl,
  }) {
    return _RevenueAgent(
      id: id ?? this.id,
      fullName: fullName ?? this.fullName,
      gender: gender ?? this.gender,
      phone: phone ?? this.phone,
      commune: commune ?? this.commune,
      identifier: identifier ?? this.identifier,
      password: password ?? this.password,
      enabled: enabled ?? this.enabled,
      localOnly: localOnly ?? this.localOnly,
      photoBase64: photoBase64 ?? this.photoBase64,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nom': fullName,
        'genre': gender,
        'telephone': phone,
        'commune': commune,
        'identifiant_unique': identifier,
        'mot_de_passe': password,
        'photo': photoBase64,
        'photo_url': photoUrl,
        'actif': enabled,
        'local_only': localOnly,
        'updated_at': DateTime.now().toIso8601String(),
      };

  factory _RevenueAgent.fromJson(Map<String, dynamic> json) => _RevenueAgent(
        id: (json['id'] ?? json['identifiant_unique'] ?? '').toString(),
        fullName: (json['nom'] ?? '').toString(),
        gender: (json['genre'] ?? 'Masculin').toString(),
        phone: (json['telephone'] ?? '').toString(),
        commune: (json['commune'] ?? '').toString(),
        identifier: (json['identifiant_unique'] ?? '').toString(),
        password: (json['mot_de_passe'] ?? '').toString(),
        enabled: json['actif'] != false,
        localOnly: json['local_only'] == true,
        photoBase64: json['photo']?.toString(),
        photoUrl: json['photo_url']?.toString(),
      );
}

class _RevenueAdmin {
  const _RevenueAdmin({
    required this.id,
    required this.name,
    required this.role,
    required this.login,
    required this.password,
    required this.localOnly,
    required this.isSuperAdmin,
    this.createdByAdminId,
  });

  final String id;
  final String name;
  final String role;
  final String login;
  final String password;
  final bool localOnly;
  final bool isSuperAdmin;
  final String? createdByAdminId;

  _RevenueAdmin copyWith({
    String? id,
    String? name,
    String? role,
    String? login,
    String? password,
    bool? localOnly,
    bool? isSuperAdmin,
    String? createdByAdminId,
  }) {
    return _RevenueAdmin(
      id: id ?? this.id,
      name: name ?? this.name,
      role: role ?? this.role,
      login: login ?? this.login,
      password: password ?? this.password,
      localOnly: localOnly ?? this.localOnly,
      isSuperAdmin: isSuperAdmin ?? this.isSuperAdmin,
      createdByAdminId: createdByAdminId ?? this.createdByAdminId,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nom': name,
        'role': role,
        'login': login,
        'mot_de_passe': password,
        'local_only': localOnly,
        'is_super_admin': isSuperAdmin,
        'created_by_admin_id': createdByAdminId,
        'updated_at': DateTime.now().toIso8601String(),
      };

  factory _RevenueAdmin.fromJson(Map<String, dynamic> json) => _RevenueAdmin(
        id: (json['id'] ?? '').toString(),
        name: (json['nom'] ?? '').toString(),
        role: (json['role'] ?? '').toString(),
        login: (json['login'] ?? '').toString(),
        password: (json['mot_de_passe'] ?? '').toString(),
        localOnly: json['local_only'] == true,
        isSuperAdmin: json['is_super_admin'] == true ||
            (json['role'] ?? '').toString().toUpperCase() == 'SUPER_ADMIN',
        createdByAdminId: json['created_by_admin_id']?.toString(),
      );
}

class _RevenueTransaction {
  const _RevenueTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.taxpayerName,
    required this.date,
    required this.agentId,
    required this.agentName,
    required this.commune,
    required this.status,
    required this.comment,
    required this.localOnly,
  });

  final String id;
  final double amount;
  final String type;
  final String taxpayerName;
  final DateTime date;
  final String agentId;
  final String agentName;
  final String commune;
  final String status;
  final String comment;
  final bool localOnly;

  _RevenueTransaction copyWith({
    String? id,
    double? amount,
    String? type,
    String? taxpayerName,
    DateTime? date,
    String? agentId,
    String? agentName,
    String? commune,
    String? status,
    String? comment,
    bool? localOnly,
  }) {
    return _RevenueTransaction(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      taxpayerName: taxpayerName ?? this.taxpayerName,
      date: date ?? this.date,
      agentId: agentId ?? this.agentId,
      agentName: agentName ?? this.agentName,
      commune: commune ?? this.commune,
      status: status ?? this.status,
      comment: comment ?? this.comment,
      localOnly: localOnly ?? this.localOnly,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'numero_transaction': id,
        'montant': amount,
        'type': type,
        'contribuable': taxpayerName,
        'date': date.toIso8601String(),
        'agent_id': agentId,
        'agent_nom': agentName,
        'commune': commune,
        'statut': status,
        'commentaire': comment,
        'local_only': localOnly,
        'updated_at': DateTime.now().toIso8601String(),
      };

  factory _RevenueTransaction.fromJson(Map<String, dynamic> json) => _RevenueTransaction(
        id: (json['id'] ?? json['numero_transaction'] ?? '').toString(),
        amount: (json['montant'] is num)
            ? (json['montant'] as num).toDouble()
            : double.tryParse('${json['montant']}') ?? 0,
        type: (json['type'] ?? '').toString(),
        taxpayerName: (json['contribuable'] ?? '').toString(),
        date: DateTime.tryParse((json['date'] ?? '').toString()) ?? DateTime.now(),
        agentId: (json['agent_id'] ?? '').toString(),
        agentName: (json['agent_nom'] ?? '').toString(),
        commune: (json['commune'] ?? '').toString(),
        status: (json['statut'] ?? 'EN_ATTENTE').toString(),
        comment: (json['commentaire'] ?? '').toString(),
        localOnly: json['local_only'] == true,
      );
}
