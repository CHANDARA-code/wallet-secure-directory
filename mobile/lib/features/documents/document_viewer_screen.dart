import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import 'document_viewer_notifier.dart';
import 'documents_notifier.dart';

class DocumentViewerScreen extends ConsumerStatefulWidget {
  final String documentId;

  const DocumentViewerScreen({super.key, required this.documentId});

  @override
  ConsumerState<DocumentViewerScreen> createState() =>
      _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  late final DecryptedDocumentNotifier _viewerNotifier;

  @override
  void initState() {
    super.initState();
    _viewerNotifier = ref.read(decryptedDocumentNotifierProvider.notifier);
  }

  @override
  void dispose() {
    _viewerNotifier.clearDeferred();
    super.dispose();
  }

  Future<void> _reAuthenticate() async {
    final result = await ref
        .read(documentsNotifierProvider.notifier)
        .unlockDocument(widget.documentId);

    if (!mounted) return;

    if (result is DocumentUnlockFailure) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final decrypted = ref.watch(decryptedDocumentNotifierProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final statusColors = context.statusColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Driving License')),
      body: decrypted == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 64,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Document Locked',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'In-memory protection locked this document. Authenticate to view again.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _reAuthenticate,
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Unlock with Biometrics'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.badge_outlined,
                                  color: colorScheme.primary,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'DRIVING LICENSE',
                                      style: TextStyle(
                                        fontSize: 12,
                                        letterSpacing: 1.2,
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      decrypted.document.documentNumber,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColors.success.withValues(
                                    alpha: 0.15,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'VALID',
                                  style: TextStyle(
                                    color: statusColors.success,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 32),
                          _DetailRow(
                            label: 'Full Name',
                            value: decrypted.document.data.fullName,
                          ),
                          _DetailRow(
                            label: 'Date of Birth',
                            value: decrypted.document.data.dateOfBirth,
                          ),
                          _DetailRow(
                            label: 'Nationality',
                            value: decrypted.document.data.nationality,
                          ),
                          _DetailRow(
                            label: 'Address',
                            value: decrypted.document.data.address,
                          ),
                          _DetailRow(
                            label: 'Issuing Authority',
                            value: decrypted.document.data.issuingAuthority,
                          ),
                          _DetailRow(
                            label: 'Issue Date',
                            value: decrypted.document.data.issueDate,
                          ),
                          _DetailRow(
                            label: 'Expiry Date',
                            value: decrypted.document.data.expiryDate,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'License Classes',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: decrypted.document.data.licenseClasses
                                .map(
                                  (c) => Chip(
                                    label: Text(
                                      c,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                          if (decrypted
                              .document
                              .data
                              .restrictions
                              .isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'Restrictions',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children: decrypted.document.data.restrictions
                                  .map((r) => Chip(label: Text(r)))
                                  .toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
