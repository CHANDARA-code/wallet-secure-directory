import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../auth/auth_notifier.dart';
import '../auth/auth_state.dart';
import '../wallet/wallet_provisioner.dart';
import 'document_model.dart';
import 'document_viewer_screen.dart';
import 'documents_notifier.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _provisioningDocumentId;

  Future<void> _handleUnlock(BuildContext context, String documentId) async {
    final result = await ref
        .read(documentsNotifierProvider.notifier)
        .unlockDocument(documentId);

    if (!context.mounted) return;

    switch (result) {
      case DocumentUnlockSuccess():
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DocumentViewerScreen(documentId: documentId),
          ),
        );
      case DocumentUnlockFailure(:final message):
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _handleAddToWallet(
    BuildContext context,
    String documentId,
  ) async {
    if (_provisioningDocumentId != null) return;
    setState(() {
      _provisioningDocumentId = documentId;
    });

    try {
      final authState = ref.read(authNotifierProvider);
      if (authState is! Authenticated) return;

      final provisioner = ref.read(walletProvisionerProvider);
      final result = await provisioner.provision(
        documentId: documentId,
        token: authState.token,
      );

      if (!context.mounted) return;

      switch (result) {
        case WalletProvisionStubError(:final message):
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        case WalletProvisionFailure(:final message):
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        case WalletProvisionUnavailable(:final message):
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        case WalletProvisionSuccess():
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pass added to wallet.')),
          );
        case WalletProvisionCancelled():
          break;
        case WalletProvisionBusy():
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _provisioningDocumentId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final documentsState = ref.watch(documentsNotifierProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final statusColors = context.statusColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Identity Wallet',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            key: const Key('theme_toggle_button'),
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: 'Toggle Theme',
            onPressed: () {
              ref
                  .read(themeModeProvider.notifier)
                  .toggle(Theme.of(context).brightness);
            },
          ),
          IconButton(
            key: const Key('sign_out_button'),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign Out',
            onPressed: () {
              ref.read(authNotifierProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: switch (documentsState) {
        DocumentsLoading() => const Center(child: CircularProgressIndicator()),
        DocumentsError(:final message) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.error),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    ref
                        .read(documentsNotifierProvider.notifier)
                        .loadDocuments();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        DocumentsEmpty() => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_open_outlined,
                  size: 48,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  'No documents found',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your issued credentials will appear here.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    ref
                        .read(documentsNotifierProvider.notifier)
                        .loadDocuments();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ),
        ),
        DocumentsLoaded(:final documents) => RefreshIndicator(
          onRefresh: () async {
            await ref.read(documentsNotifierProvider.notifier).loadDocuments();
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final doc = documents[index];
              return _DocumentCard(
                document: doc,
                statusSuccessColor: statusColors.success,
                isProvisioning: _provisioningDocumentId == doc.id,
                onView: () => _handleUnlock(context, doc.id),
                onAddToWallet: () => _handleAddToWallet(context, doc.id),
                onSaveOffline: () {
                  ref
                      .read(documentsNotifierProvider.notifier)
                      .storeDocumentOffline(doc.id);
                },
              );
            },
          ),
        ),
      },
    );
  }
}

class _DocumentCard extends StatelessWidget {
  final DocumentSummary document;
  final Color statusSuccessColor;
  final VoidCallback onView;
  final VoidCallback onAddToWallet;
  final VoidCallback onSaveOffline;
  final bool isProvisioning;

  const _DocumentCard({
    required this.document,
    required this.statusSuccessColor,
    required this.onView,
    required this.onAddToWallet,
    required this.onSaveOffline,
    this.isProvisioning = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.directions_car_outlined,
                    color: colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Driving License',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        document.documentNumber,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
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
                    color: statusSuccessColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    document.status.toUpperCase(),
                    style: TextStyle(
                      color: statusSuccessColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (document.isStoredOffline)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusSuccessColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: statusSuccessColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.offline_pin_outlined,
                          size: 14,
                          color: statusSuccessColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Stored offline',
                          style: TextStyle(
                            fontSize: 12,
                            color: statusSuccessColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: onSaveOffline,
                    icon: const Icon(
                      Icons.download_for_offline_outlined,
                      size: 16,
                    ),
                    label: const Text('Save Offline'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.fingerprint, size: 18),
                    label: const Text('View Document'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isProvisioning ? null : onAddToWallet,
                    icon: isProvisioning
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 18,
                          ),
                    label: const Text('Add to OS Wallet'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
