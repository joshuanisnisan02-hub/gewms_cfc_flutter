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
  late Future<List<Map<String, dynamic>>> receiptsFuture = loadReceipts();
  bool uploading = false;
  String? error;

  Future<List<Map<String, dynamic>>> loadReceipts() async {
    final rows = await widget.supabase.from('gas_receipts').select().eq('transaction_id', widget.row['id']).order('uploaded_at', ascending: false);
    return rows.map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row)).toList();
  }

  void refreshReceipts() => setState(() => receiptsFuture = loadReceipts());

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

    final storagePath = 'transactions/${widget.row['id']}/${DateTime.now().millisecondsSinceEpoch}_${safeFilePart(file.name)}';

    setState(() {
      uploading = true;
      error = null;
    });
    try {
      await widget.supabase.storage.from('gas-receipts').uploadBinary(
            storagePath,
            file.bytes,
            fileOptions: FileOptions(contentType: file.contentType, upsert: false),
          );
      await widget.supabase.from('gas_receipts').insert({
        'transaction_id': widget.row['id'],
        'file_path': storagePath,
        'file_name': file.name,
        'content_type': file.contentType,
        'uploaded_by': widget.supabase.auth.currentUser?.id,
      });
      refreshReceipts();
    } catch (e) {
      setState(() => error = cleanError(e));
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> replaceReceipt(Map<String, dynamic> receipt) async {
    final oldPath = receipt['file_path']?.toString();
    final receiptId = receipt['id'];
    if (receiptId == null || oldPath == null || oldPath.isEmpty) return;

    final file = await pickReceiptFile();
    if (file == null) return;

    final newPath = 'transactions/${widget.row['id']}/${DateTime.now().millisecondsSinceEpoch}_${safeFilePart(file.name)}';

    setState(() {
      uploading = true;
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
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> deleteReceipt(Map<String, dynamic> receipt) async {
    final filePath = receipt['file_path']?.toString();
    final receiptId = receipt['id'];
    if (receiptId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete receipt?'),
        content: Text('This will remove ${receipt['file_name'] ?? 'this receipt'} from the transaction.'),
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
      uploading = true;
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
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> showSignedLink(Map<String, dynamic> receipt) async {
    final filePath = receipt['file_path']?.toString();
    if (filePath == null || filePath.isEmpty) return;

    setState(() {
      uploading = true;
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
      if (mounted) setState(() => uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    return Scaffold(
      appBar: AppBar(title: Text(row['transaction_no']?.toString() ?? 'Gas transaction')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: uploading ? null : uploadReceipt,
        icon: const Icon(Icons.upload_file),
        label: const Text('Upload receipt'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (uploading) const LinearProgressIndicator(),
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
                          enabled: !uploading,
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

String cleanError(Object? error) {
  final text = error.toString().replaceFirst('Exception: ', '');
  return text.length > 300 ? '${text.substring(0, 300)}...' : text;
}

String dateText(dynamic value) => value == null ? '-' : value.toString().split('T').first;
String safeFilePart(String value) => value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

String contentTypeForName(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  return 'application/octet-stream';
}
