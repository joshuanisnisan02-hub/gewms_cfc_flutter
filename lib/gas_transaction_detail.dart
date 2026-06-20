import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GasTransactionDetailScreen extends StatefulWidget {
  const GasTransactionDetailScreen({super.key, required this.row, required this.supabase});

  final Map<String, dynamic> row;
  final SupabaseClient supabase;

  @override
  State<GasTransactionDetailScreen> createState() => _GasTransactionDetailScreenState();
}

class _GasTransactionDetailScreenState extends State<GasTransactionDetailScreen> {
  late Map<String, dynamic> row = Map<String, dynamic>.from(widget.row);
  late Future<List<Map<String, dynamic>>> receiptsFuture = loadReceipts();
  bool busy = false;
  String? error;

  Future<List<Map<String, dynamic>>> loadReceipts() async {
    final rows = await widget.supabase.from('gas_receipts').select().eq('transaction_id', row['id']).order('uploaded_at', ascending: false);
    return rows.map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row)).toList();
  }

  void refreshReceipts() => setState(() => receiptsFuture = loadReceipts());

  Future<void> refreshTransaction() async {
    final id = row['id'];
    if (id == null) return;
    final updated = await widget.supabase.from('gas_transactions').select().eq('id', id).maybeSingle();
    if (updated != null && mounted) setState(() => row = Map<String, dynamic>.from(updated));
  }

  Future<PickedReceipt?> pickReceiptFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return null;

    final file = picked.files.single;
    final Uint8List? bytes = file.bytes;
    if (bytes == null) {
      setState(() => error = 'Could not read the selected file. Try a smaller file or a different picker.');
      return null;
    }

    return PickedReceipt(
      name: file.name,
      bytes: bytes,
      contentType: contentTypeForName(file.name),
    );
  }

  Future<void> uploadReceipt() async {
    final file = await pickReceiptFile();
    if (file == null) return;

    final storagePath = receiptPath(file.name);

    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.supabase.storage.from('gas-receipts').uploadBinary(
            storagePath,
            file.bytes,
            fileOptions: FileOptions(contentType: file.contentType, upsert: false),
          );
      await widget.supabase.from('gas_receipts').insert({
        'transaction_id': row['id'],
        'file_path': storagePath,
        'file_name': file.name,
        'content_type': file.contentType,
        'uploaded_by': widget.supabase.auth.currentUser?.id,
      });
      refreshReceipts();
    } catch (e) {
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> replaceReceipt(Map<String, dynamic> receipt) async {
    final oldPath = receipt['file_path']?.toString();
    final receiptId = receipt['id'];
    if (receiptId == null || oldPath == null || oldPath.isEmpty) return;

    final file = await pickReceiptFile();
    if (file == null) return;

    final newPath = receiptPath(file.name);

    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.supabase.storage.from('gas-receipts').uploadBinary(
            newPath,
            file.bytes,
            fileOptions: FileOptions(contentType: file.contentType, upsert: false),
          );
      await widget.supabase.from('gas_receipts').update({
        'file_path': newPath,
        'file_name': file.name,
        'content_type': file.contentType,
        'uploaded_by': widget.supabase.auth.currentUser?.id,
        'uploaded_at': DateTime.now().toIso8601String(),
      }).eq('id', receiptId);
      await widget.supabase.storage.from('gas-receipts').remove([oldPath]);
      refreshReceipts();
    } catch (e) {
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deleteReceipt(Map<String, dynamic> receipt) async {
    final filePath = receipt['file_path']?.toString();
    final receiptId = receipt['id'];
    if (receiptId == null) return;

    final confirmed = await confirm(
      title: 'Delete receipt?',
      message: 'This will remove ${receipt['file_name'] ?? 'this receipt'} from the transaction.',
      action: 'Delete',
    );
    if (!confirmed) return;

    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.supabase.from('gas_receipts').delete().eq('id', receiptId);
      if (filePath != null && filePath.isNotEmpty) {
        await widget.supabase.storage.from('gas-receipts').remove([filePath]);
      }
      refreshReceipts();
    } catch (e) {
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> showSignedLink(Map<String, dynamic> receipt) async {
    final filePath = receipt['file_path']?.toString();
    if (filePath == null || filePath.isEmpty) return;

    setState(() {
      busy = true;
      error = null;
    });
    try {
      final url = await widget.supabase.storage.from('gas-receipts').createSignedUrl(filePath, 600);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(receipt['file_name']?.toString() ?? 'Receipt link'),
          content: SelectableText(url),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } catch (e) {
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editTransaction() async {
    final saved = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => GasTransactionFormDialog(row: row),
    );
    if (saved == null || row['id'] == null) return;

    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.supabase.from('gas_transactions').update(saved).eq('id', row['id']);
      await refreshTransaction();
    } catch (e) {
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> updateStatus(String status) async {
    if (row['id'] == null) return;

    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.supabase.from('gas_transactions').update({'status': status}).eq('id', row['id']);
      setState(() => row = {...row, 'status': status});
    } catch (e) {
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deleteTransaction() async {
    if (row['id'] == null) return;

    final confirmed = await confirm(
      title: 'Delete transaction?',
      message: 'This will delete ${row['transaction_no'] ?? 'this transaction'} and remove its uploaded receipts. This cannot be undone.',
      action: 'Delete',
    );
    if (!confirmed) return;

    setState(() {
      busy = true;
      error = null;
    });
    try {
      final receipts = await widget.supabase.from('gas_receipts').select('id,file_path').eq('transaction_id', row['id']);
      final paths = receipts.map<String?>((receipt) => receipt['file_path']?.toString()).whereType<String>().where((path) => path.isNotEmpty).toList();

      await widget.supabase.from('gas_receipts').delete().eq('transaction_id', row['id']);
      await widget.supabase.from('gas_transactions').delete().eq('id', row['id']);
      if (paths.isNotEmpty) await widget.supabase.storage.from('gas-receipts').remove(paths);

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm({required String title, required String message, required String action}) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              FilledButton.tonalIcon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.delete),
                label: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  String receiptPath(String fileName) => 'transactions/${row['id']}/${DateTime.now().millisecondsSinceEpoch}_${safeFilePart(fileName)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(row['transaction_no']?.toString() ?? 'Gas transaction'),
        actions: [
          PopupMenuButton<String>(
            enabled: !busy,
            onSelected: (value) {
              if (value == 'edit') editTransaction();
              if (value == 'pending') updateStatus('Pending');
              if (value == 'completed') updateStatus('Completed');
              if (value == 'cancelled') updateStatus('Cancelled');
              if (value == 'delete') deleteTransaction();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('Edit details'))),
              PopupMenuDivider(),
              PopupMenuItem(value: 'pending', child: ListTile(leading: Icon(Icons.pending_actions), title: Text('Mark Pending'))),
              PopupMenuItem(value: 'completed', child: ListTile(leading: Icon(Icons.check_circle), title: Text('Mark Completed'))),
              PopupMenuItem(value: 'cancelled', child: ListTile(leading: Icon(Icons.cancel), title: Text('Mark Cancelled'))),
              PopupMenuDivider(),
              PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete), title: Text('Delete transaction'))),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy ? null : uploadReceipt,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload receipt'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text(error!))),
          Card(
            child: Column(
              children: [
                detailTile('Transaction no', row['transaction_no']),
                detailTile('Driver', row['driver_name']),
                detailTile('Vehicle', '${row['car_description'] ?? ''} ${row['plate_number'] ?? ''}'.trim()),
                detailTile('Date from', dateText(row['date_from'])),
                detailTile('Date to', dateText(row['date_to'])),
                detailTile('Route', '${row['destination_from'] ?? ''} to ${row['destination_to'] ?? ''}'),
                detailTile('Status', row['status'] ?? 'Pending'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Receipts', style: Theme.of(context).textTheme.titleLarge),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: receiptsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
              if (snapshot.hasError) return Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text(cleanError(snapshot.error))));
              final receipts = snapshot.data!;
              if (receipts.isEmpty) return const Card(child: ListTile(title: Text('No receipts uploaded yet.')));
              return Column(
                children: [
                  for (final receipt in receipts)
                    Card(
                      child: ListTile(
                        leading: Icon((receipt['content_type'] ?? '').toString().contains('pdf') ? Icons.picture_as_pdf : Icons.image),
                        title: Text(receipt['file_name']?.toString() ?? receipt['file_path']?.toString() ?? 'Receipt'),
                        subtitle: Text('Uploaded: ${dateText(receipt['uploaded_at'])}\nPath: ${receipt['file_path'] ?? '-'}'),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          enabled: !busy,
                          onSelected: (value) {
                            if (value == 'link') showSignedLink(receipt);
                            if (value == 'replace') replaceReceipt(receipt);
                            if (value == 'delete') deleteReceipt(receipt);
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'link', child: Text('Create link')),
                            PopupMenuItem(value: 'replace', child: Text('Replace file')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 96),
        ],
      ),
    );
  }
}

class GasTransactionFormDialog extends StatefulWidget {
  const GasTransactionFormDialog({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  State<GasTransactionFormDialog> createState() => _GasTransactionFormDialogState();
}

class _GasTransactionFormDialogState extends State<GasTransactionFormDialog> {
  final formKey = GlobalKey<FormState>();
  final transactionNo = TextEditingController();
  final driverName = TextEditingController();
  final carDescription = TextEditingController();
  final plateNumber = TextEditingController();
  final dateFrom = TextEditingController();
  final dateTo = TextEditingController();
  final destinationFrom = TextEditingController();
  final destinationTo = TextEditingController();
  String status = 'Pending';

  @override
  void initState() {
    super.initState();
    final row = widget.row;
    transactionNo.text = row['transaction_no']?.toString() ?? '';
    driverName.text = row['driver_name']?.toString() ?? '';
    carDescription.text = row['car_description']?.toString() ?? '';
    plateNumber.text = row['plate_number']?.toString() ?? '';
    dateFrom.text = dateInput(row['date_from']);
    dateTo.text = dateInput(row['date_to']);
    destinationFrom.text = row['destination_from']?.toString() ?? '';
    destinationTo.text = row['destination_to']?.toString() ?? '';
    status = row['status']?.toString() ?? 'Pending';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit gas transaction'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                requiredField(transactionNo, 'Transaction no'),
                textField(driverName, 'Driver name'),
                textField(carDescription, 'Vehicle description'),
                textField(plateNumber, 'Plate number'),
                textField(dateFrom, 'Date from YYYY-MM-DD'),
                textField(dateTo, 'Date to YYYY-MM-DD'),
                textField(destinationFrom, 'Destination from'),
                textField(destinationTo, 'Destination to'),
                DropdownButtonFormField<String>(
                  value: status,
                  decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                    DropdownMenuItem(value: 'Cancelled', child: Text('Cancelled')),
                  ],
                  onChanged: (value) => setState(() => status = value ?? 'Pending'),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!formKey.currentState!.validate()) return;
            Navigator.pop(context, {
              'transaction_no': transactionNo.text.trim(),
              'driver_name': nullableText(driverName.text),
              'car_description': nullableText(carDescription.text),
              'plate_number': nullableText(plateNumber.text),
              'date_from': nullableText(dateFrom.text),
              'date_to': nullableText(dateTo.text),
              'destination_from': nullableText(destinationFrom.text),
              'destination_to': nullableText(destinationTo.text),
              'status': status,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class PickedReceipt {
  const PickedReceipt({required this.name, required this.bytes, required this.contentType});
  final String name;
  final Uint8List bytes;
  final String contentType;
}

Widget detailTile(String label, dynamic value) => ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text(value == null || value.toString().isEmpty ? '-' : value.toString()),
    );

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

String? nullableText(String value) => value.trim().isEmpty ? null : value.trim();
String dateText(dynamic value) => value == null ? '-' : value.toString().split('T').first;
String dateInput(dynamic value) => value == null ? '' : value.toString().split('T').first;
String safeFilePart(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

String contentTypeForName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  return 'application/octet-stream';
}
