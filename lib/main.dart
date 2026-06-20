import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gas_transaction_detail.dart';

const supabaseUrl = 'https://laonbefisynknlnzcnkt.supabase.co';
const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (supabaseKey.isNotEmpty) {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseKey);
  }
  runApp(const GewmsApp());
}

final supabase = Supabase.instance.client;

class GewmsApp extends StatelessWidget {
  const GewmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'GEWMS CFC',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
        useMaterial3: true,
      ),
      home: supabaseKey.isEmpty ? const ConfigScreen() : const AuthGate(),
    );
  }
}

class ConfigScreen extends StatelessWidget {
  const ConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Missing SUPABASE_KEY. Run with: flutter run --dart-define=SUPABASE_KEY=your_publishable_key',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;
        return session == null ? const LoginScreen() : const HomeShell();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final secret = TextEditingController();
  bool loading = false;
  String? error;

  Future<void> signIn() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await supabase.auth.signInWithPassword(
        email: email.text.trim(),
        password: secret.text,
      );
    } catch (e) {
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.energy_savings_leaf, size: 64),
                  const SizedBox(height: 12),
                  Text('GEWMS CFC', style: Theme.of(context).textTheme.headlineMedium),
                  const Text('Gas, Electricity and Water Monitoring System'),
                  const SizedBox(height: 24),
                  TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
                  const SizedBox(height: 12),
                  TextField(controller: secret, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
                  if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: loading ? null : signIn,
                    icon: loading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
                    label: const Text('Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;
  Map<String, dynamic>? profile;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    final rows = await supabase.from('profiles').select('email,role,driver_id,full_name').eq('id', user.id).limit(1);
    if (mounted && rows.isNotEmpty) setState(() => profile = Map<String, dynamic>.from(rows.first));
  }

  bool get isAdmin => (profile?['role'] ?? '').toString().toLowerCase() == 'admin';

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const DashboardScreen(),
      const BillingScreen(title: 'Water Bills', table: 'water_bills', usageColumn: 'cubic_meter_used'),
      const BillingScreen(title: 'Electricity Bills', table: 'electricity_bills', usageColumn: 'khw_used'),
      GasTransactionsScreen(driverId: isAdmin ? null : asInt(profile?['driver_id'])),
      const MasterDataScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('GEWMS CFC'),
        actions: [
          Center(child: Text(profile?['full_name'] ?? profile?['email'] ?? 'Signed in')),
          IconButton(onPressed: () => supabase.auth.signOut(), icon: const Icon(Icons.logout), tooltip: 'Logout'),
        ],
      ),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.water_drop), label: 'Water'),
          NavigationDestination(icon: Icon(Icons.bolt), label: 'Electricity'),
          NavigationDestination(icon: Icon(Icons.local_gas_station), label: 'Gas'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Data'),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<Map<String, dynamic>> future = load();

  Future<Map<String, dynamic>> load() async {
    final water = await supabase.from('water_bills').select('amount,status');
    final electric = await supabase.from('electricity_bills').select('amount,date_paid');
    final gas = await supabase.from('gas_transactions').select('id,status');
    return {
      'waterCount': water.length,
      'electricCount': electric.length,
      'gasCount': gas.length,
      'waterPending': sumAmount(water.where((r) => (r['status'] ?? 'Pending') == 'Pending')),
      'electricUnpaid': sumAmount(electric.where((r) => r['date_paid'] == null)),
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return ErrorView(error: snapshot.error, onRetry: () => setState(() => future = load()));
        final data = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => setState(() => future = load()),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Dashboard', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              Wrap(children: [
                MetricCard(label: 'Water bills', value: '${data['waterCount']}', icon: Icons.water_drop),
                MetricCard(label: 'Electricity bills', value: '${data['electricCount']}', icon: Icons.bolt),
                MetricCard(label: 'Gas trips', value: '${data['gasCount']}', icon: Icons.local_gas_station),
                MetricCard(label: 'Pending water', value: peso(data['waterPending']), icon: Icons.pending_actions),
                MetricCard(label: 'Unpaid electricity', value: peso(data['electricUnpaid']), icon: Icons.receipt_long),
              ]),
            ],
          ),
        );
      },
    );
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(icon, size: 36),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), Text(value, style: Theme.of(context).textTheme.titleLarge)])),
          ]),
        ),
      ),
    );
  }
}

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key, required this.title, required this.table, required this.usageColumn});
  final String title;
  final String table;
  final String usageColumn;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  late Future<List<Map<String, dynamic>>> future = load();

  bool get isWater => widget.table == 'water_bills';

  Future<List<Map<String, dynamic>>> load() async {
    final rows = await supabase.from(widget.table).select().order('month_billed', ascending: false);
    return rows.map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row)).toList();
  }

  void refresh() => setState(() => future = load());

  Future<void> add() async {
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => BillingFormDialog(title: 'Add ${widget.title}', usageColumn: widget.usageColumn, isWater: isWater),
    );
    if (saved == null) return;
    await supabase.from(widget.table).insert(saved);
    refresh();
  }

  Future<void> markPaid(Map<String, dynamic> row) async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await supabase.from(widget.table).update(isWater ? {'date_paid': today, 'status': 'Paid'} : {'date_paid': today}).eq('id', row['id']);
    refresh();
  }

  Future<void> openDetails(Map<String, dynamic> row) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BillingDetailScreen(
          title: widget.title,
          table: widget.table,
          usageColumn: widget.usageColumn,
          isWater: isWater,
          row: row,
        ),
      ),
    );
    if (changed == true) refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return ErrorView(error: snapshot.error, onRetry: refresh);
        final rows = snapshot.data!;
        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(onPressed: add, icon: const Icon(Icons.add), label: const Text('Add bill')),
          body: RefreshIndicator(
            onRefresh: () async => refresh(),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(widget.title, style: Theme.of(context).textTheme.headlineMedium),
                if (rows.isEmpty) const Card(child: ListTile(title: Text('No records yet.'))),
                for (final row in rows)
                  Card(
                    child: ListTile(
                      title: Text('${row['billing_id'] ?? 'No billing id'} • ${row['account_number'] ?? ''}'),
                      subtitle: Text('Month: ${dateText(row['month_billed'])} • Usage: ${row[widget.usageColumn] ?? 0} • Due: ${dateText(row['due_date'])}\nAmount: ${peso(row['amount'])} • Paid: ${row['date_paid'] == null ? 'No' : dateText(row['date_paid'])}'),
                      isThreeLine: true,
                      onTap: () => openDetails(row),
                      trailing: row['date_paid'] == null ? TextButton(onPressed: () => markPaid(row), child: const Text('Paid')) : const Icon(Icons.check_circle),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class BillingDetailScreen extends StatefulWidget {
  const BillingDetailScreen({super.key, required this.title, required this.table, required this.usageColumn, required this.isWater, required this.row});
  final String title;
  final String table;
  final String usageColumn;
  final bool isWater;
  final Map<String, dynamic> row;

  @override
  State<BillingDetailScreen> createState() => _BillingDetailScreenState();
}

class _BillingDetailScreenState extends State<BillingDetailScreen> {
  late Map<String, dynamic> row = Map<String, dynamic>.from(widget.row);
  bool saving = false;
  String? error;

  Future<void> edit() async {
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => BillingFormDialog(
        title: 'Edit ${widget.title}',
        usageColumn: widget.usageColumn,
        isWater: widget.isWater,
        initialRow: row,
      ),
    );
    if (saved == null) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await supabase.from(widget.table).update(saved).eq('id', row['id']);
      setState(() => row = {...row, ...saved});
    } catch (e) {
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> markPaid() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final update = widget.isWater ? {'date_paid': today, 'status': 'Paid'} : {'date_paid': today};
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await supabase.from(widget.table).update(update).eq('id', row['id']);
      setState(() => row = {...row, ...update});
    } catch (e) {
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> deleteBill() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete bill?'),
        content: Text('This will permanently delete ${row['billing_id'] ?? 'this bill'}. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await supabase.from(widget.table).delete().eq('id', row['id']);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(row['billing_id']?.toString() ?? widget.title),
        actions: [
          IconButton(onPressed: saving ? null : edit, icon: const Icon(Icons.edit), tooltip: 'Edit'),
          IconButton(onPressed: saving ? null : deleteBill, icon: const Icon(Icons.delete), tooltip: 'Delete'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (saving) const LinearProgressIndicator(),
          if (error != null) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text(error!))),
          Card(
            child: Column(
              children: [
                detailTile('Billing ID', row['billing_id']),
                detailTile('Account number', row['account_number']),
                detailTile('Office ID', row['office_id']),
                detailTile('Meter number', row['meter_number']),
                detailTile('Month billed', dateText(row['month_billed'])),
                detailTile('Period from', dateText(row['period_from'])),
                detailTile('Period to', dateText(row['period_to'])),
                detailTile('Due date', dateText(row['due_date'])),
                detailTile('Previous reading', row['previous_reading']),
                detailTile('Present reading', row['present_reading']),
                detailTile('Usage', row[widget.usageColumn]),
                detailTile('Amount', peso(row['amount'])),
                detailTile('Date paid', row['date_paid'] == null ? 'Not paid' : dateText(row['date_paid'])),
                if (widget.isWater) detailTile('Status', row['status'] ?? 'Pending'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (row['date_paid'] == null)
            FilledButton.icon(
              onPressed: saving ? null : markPaid,
              icon: const Icon(Icons.check_circle),
              label: const Text('Mark as paid'),
            ),
        ],
      ),
    );
  }
}

Widget detailTile(String label, dynamic value) => ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text(value == null || value.toString().isEmpty ? '-' : value.toString()),
    );

class BillingFormDialog extends StatefulWidget {
  const BillingFormDialog({super.key, required this.title, required this.usageColumn, required this.isWater, this.initialRow});
  final String title;
  final String usageColumn;
  final bool isWater;
  final Map<String, dynamic>? initialRow;

  @override
  State<BillingFormDialog> createState() => _BillingFormDialogState();
}

class _BillingFormDialogState extends State<BillingFormDialog> {
  final formKey = GlobalKey<FormState>();
  final billingId = TextEditingController();
  final accountNumber = TextEditingController();
  final officeId = TextEditingController();
  final meterNumber = TextEditingController();
  final monthBilled = TextEditingController();
  final periodFrom = TextEditingController();
  final periodTo = TextEditingController();
  final dueDate = TextEditingController();
  final presentReading = TextEditingController(text: '0');
  final previousReading = TextEditingController(text: '0');
  final amount = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    final row = widget.initialRow;
    if (row == null) {
      billingId.text = '${widget.isWater ? 'WB' : 'EB'}-${DateTime.now().millisecondsSinceEpoch}';
      return;
    }
    billingId.text = row['billing_id']?.toString() ?? '';
    accountNumber.text = row['account_number']?.toString() ?? '';
    officeId.text = row['office_id']?.toString() ?? '';
    meterNumber.text = row['meter_number']?.toString() ?? '';
    monthBilled.text = dateInput(row['month_billed']);
    periodFrom.text = dateInput(row['period_from']);
    periodTo.text = dateInput(row['period_to']);
    dueDate.text = dateInput(row['due_date']);
    previousReading.text = row['previous_reading']?.toString() ?? '0';
    presentReading.text = row['present_reading']?.toString() ?? '0';
    amount.text = row['amount']?.toString() ?? '0';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 520,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(children: [
              requiredField(billingId, 'Billing ID'),
              requiredField(accountNumber, 'Account number'),
              textField(officeId, 'Office ID'),
              textField(meterNumber, 'Meter number'),
              requiredField(monthBilled, 'Month billed YYYY-MM-DD'),
              requiredField(periodFrom, 'Period from YYYY-MM-DD'),
              requiredField(periodTo, 'Period to YYYY-MM-DD'),
              requiredField(dueDate, 'Due date YYYY-MM-DD'),
              textField(previousReading, 'Previous reading'),
              textField(presentReading, 'Present reading'),
              textField(amount, 'Amount'),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            final previous = asDouble(previousReading.text);
            final present = asDouble(presentReading.text);
            Navigator.pop(context, {
              'billing_id': billingId.text.trim(),
              'account_number': accountNumber.text.trim(),
              'office_id': nullableInt(officeId.text),
              'meter_number': nullableText(meterNumber.text),
              'month_billed': monthBilled.text.trim(),
              'period_from': periodFrom.text.trim(),
              'period_to': periodTo.text.trim(),
              'due_date': dueDate.text.trim(),
              'previous_reading': previous,
              'present_reading': present,
              widget.usageColumn: present - previous,
              'amount': asDouble(amount.text),
              if (widget.isWater && widget.initialRow == null) 'status': 'Pending',
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class GasTransactionsScreen extends StatefulWidget {
  const GasTransactionsScreen({super.key, this.driverId});
  final int? driverId;

  @override
  State<GasTransactionsScreen> createState() => _GasTransactionsScreenState();
}

class _GasTransactionsScreenState extends State<GasTransactionsScreen> {
  late Future<List<Map<String, dynamic>>> future = load();

  Future<List<Map<String, dynamic>>> load() async {
    final rows = widget.driverId == null
        ? await supabase.from('gas_transactions').select().order('id', ascending: false)
        : await supabase.from('gas_transactions').select().eq('driver_id', widget.driverId!).order('id', ascending: false);
    return rows.map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row)).toList();
  }

  void refresh() => setState(() => future = load());

  Future<void> openDetails(Map<String, dynamic> row) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GasTransactionDetailScreen(row: row, supabase: supabase)));
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return ErrorView(error: snapshot.error, onRetry: refresh);
        final rows = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => refresh(),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text('Gas Transactions', style: Theme.of(context).textTheme.headlineMedium),
              if (rows.isEmpty) const Card(child: ListTile(title: Text('No transactions yet.'))),
              for (final row in rows)
                Card(
                  child: ListTile(
                    title: Text('${row['transaction_no'] ?? 'No transaction no'} • ${row['driver_name'] ?? ''}'),
                    subtitle: Text('${row['car_description'] ?? ''} ${row['plate_number'] ?? ''}\n${dateText(row['date_from'])} to ${dateText(row['date_to'])} • ${row['destination_from'] ?? ''} to ${row['destination_to'] ?? ''}'),
                    isThreeLine: true,
                    onTap: () => openDetails(row),
                    trailing: Chip(label: Text((row['status'] ?? 'Pending').toString())),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class MasterDataScreen extends StatelessWidget {
  const MasterDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: const [
        Text('Master Data', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        DataList(title: 'Offices', table: 'tbl_offices', displayColumns: ['office_id', 'office_name']),
        DataList(title: 'Buildings', table: 'tbl_bldg', displayColumns: ['building_id', 'building_name']),
        DataList(title: 'Drivers', table: 'drivers', displayColumns: ['id', 'driver_name']),
        DataList(title: 'Cars', table: 'cars', displayColumns: ['id', 'car_description', 'plate_number']),
        DataList(title: 'Water Accounts', table: 'water_accounts', displayColumns: ['id', 'account_number', 'office_id', 'building_id']),
        DataList(title: 'Electricity Accounts', table: 'electricity_account', displayColumns: ['id', 'account_number']),
      ],
    );
  }
}

class DataList extends StatefulWidget {
  const DataList({super.key, required this.title, required this.table, required this.displayColumns});
  final String title;
  final String table;
  final List<String> displayColumns;

  @override
  State<DataList> createState() => _DataListState();
}

class _DataListState extends State<DataList> {
  late Future<List<Map<String, dynamic>>> future = load();

  Future<List<Map<String, dynamic>>> load() async {
    final rows = await supabase.from(widget.table).select().limit(10);
    return rows.map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(widget.title),
        children: [
          FutureBuilder<List<Map<String, dynamic>>>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
              if (snapshot.hasError) return Padding(padding: const EdgeInsets.all(16), child: Text(cleanError(snapshot.error)));
              final rows = snapshot.data!;
              if (rows.isEmpty) return const ListTile(title: Text('No records.'));
              return Column(children: [
                for (final row in rows)
                  ListTile(dense: true, title: Text(widget.displayColumns.map((c) => '$c: ${row[c] ?? ''}').join(' • '))),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 12),
          Text(cleanError(error), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}

Widget textField(TextEditingController controller, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(controller: controller, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
    );

Widget requiredField(TextEditingController controller, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        validator: (value) => value == null || value.trim().isEmpty ? 'Required' : null,
      ),
    );

String cleanError(Object? error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  return text.length > 300 ? '${text.substring(0, 300)}...' : text;
}

int? asInt(dynamic value) => value == null ? null : int.tryParse(value.toString());
int? nullableInt(String value) => value.trim().isEmpty ? null : int.tryParse(value.trim());
String? nullableText(String value) => value.trim().isEmpty ? null : value.trim();
double asDouble(dynamic value) => double.tryParse((value ?? '0').toString()) ?? 0;
String dateText(dynamic value) => value == null ? '-' : value.toString().split('T').first;
String dateInput(dynamic value) => value == null ? '' : value.toString().split('T').first;
String peso(dynamic value) => 'PHP ${asDouble(value).toStringAsFixed(2)}';
double sumAmount(Iterable<dynamic> rows) => rows.fold<double>(0, (total, row) => total + asDouble(row['amount']));