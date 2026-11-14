import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:signature/signature.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MobileAds.instance.initialize();
  runApp(const SmartPdfScannerApp());
}

class SmartPdfScannerApp extends StatelessWidget {
  const SmartPdfScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart PDF Scanner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: ThemeMode.system,
      home: const ScannerHomePage(),
    );
  }
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key});

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

class _ScannerHomePageState extends State<ScannerHomePage> {
  final List<String> _scannedImagePaths = [];
  Uint8List? _signatureBytes;
  bool _isGenerating = false;

  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;
  InterstitialAd? _interstitialAd;

  final String _bannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';
  final String _interstitialAdUnitId = 'ca-app-pub-3940256099942544/1033173712';

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
    _loadInterstitialAd();
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: _bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() => _isBannerLoaded = true),
        onAdFailedToLoad: (ad, err) => ad.dispose(),
      ),
    )..load();
  }

  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: _interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (err) => _interstitialAd = null,
      ),
    );
  }

  Future<void> _startDocumentScan() async {
    try {
      final options = DocumentScannerOptions(
        documentFormat: DocumentFormat.jpeg,
        mode: ScannerMode.full,
        pageLimit: 10,
        isGalleryImport: true,
      );

      final documentScanner = DocumentScanner(options: options);
      final result = await documentScanner.scanDocument();

      if (result.images.isNotEmpty) {
        setState(() {
          _scannedImagePaths.addAll(result.images);
        });
      }
      documentScanner.close();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan Error: $e')),
        );
      }
    }
  }

  void _openSignaturePad() {
    final SignatureController controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.transparent,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Draw Your Signature'),
        content: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            color: Colors.white,
          ),
          height: 200,
          width: double.maxFinite,
          child: Signature(
            controller: controller,
            backgroundColor: Colors.white,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => controller.clear(),
            child: const Text('Clear'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.isNotEmpty) {
                final data = await controller.toPngBytes();
                setState(() => _signatureBytes = data);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save Signature'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportAndSharePdf() async {
    if (_scannedImagePaths.isEmpty) return;

    setState(() => _isGenerating = true);

    try {
      final pdf = pw.Document();

      for (int i = 0; i < _scannedImagePaths.length; i++) {
        final imageFile = File(_scannedImagePaths[i]);
        final imageBytes = await imageFile.readAsBytes();
        final pdfImage = pw.MemoryImage(imageBytes);

        final bool isLastPage = (i == _scannedImagePaths.length - 1);

        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Stack(
                children: [
                  pw.Center(child: pw.Image(pdfImage, fit: pw.BoxFit.contain)),
                  if (isLastPage && _signatureBytes != null)
                    pw.Positioned(
                      bottom: 40,
                      right: 40,
                      child: pw.Image(
                        pw.MemoryImage(_signatureBytes!),
                        width: 120,
                        height: 60,
                      ),
                    ),
                ],
              );
            },
          ),
        );
      }

      final outputDir = await getTemporaryDirectory();
      final filePath =
          '${outputDir.path}/Scanned_Doc_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      setState(() => _isGenerating = false);

      if (_interstitialAd != null) {
        _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            _loadInterstitialAd();
            Share.shareXFiles([XFile(filePath)], text: 'Created with Smart PDF Scanner');
          },
          onAdFailedToShowFullScreenContent: (ad, err) {
            ad.dispose();
            Share.shareXFiles([XFile(filePath)], text: 'Created with Smart PDF Scanner');
          },
        );
        _interstitialAd!.show();
      } else {
        await Share.shareXFiles([XFile(filePath)], text: 'Created with Smart PDF Scanner');
      }
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF Export Error: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart PDF Scanner'),
        actions: [
          if (_scannedImagePaths.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear All',
              onPressed: () {
                setState(() {
                  _scannedImagePaths.clear();
                  _signatureBytes = null;
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _scannedImagePaths.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.document_scanner_outlined,
                            size: 80, color: Colors.blueAccent.withOpacity(0.6)),
                        const SizedBox(height: 16),
                        const Text(
                          'No documents scanned yet',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 8),
                        const Text('Tap the Scan button below to start'),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: _scannedImagePaths.length,
                    itemBuilder: (context, index) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(_scannedImagePaths[index]),
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 6,
                            left: 6,
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.black87,
                              child: Text(
                                '${index + 1}',
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),

          if (_signatureBytes != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.green.withOpacity(0.15),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  const Text('E-Signature attached to last page'),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _signatureBytes = null),
                    child: const Text('Remove'),
                  )
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _startDocumentScan,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Scan'),
                ),
                ElevatedButton.icon(
                  onPressed: _scannedImagePaths.isEmpty ? null : _openSignaturePad,
                  icon: const Icon(Icons.draw),
                  label: const Text('Sign'),
                ),
                FilledButton.icon(
                  onPressed: (_scannedImagePaths.isEmpty || _isGenerating)
                      ? null
                      : _exportAndSharePdf,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.picture_as_pdf),
                  label: const Text('Export PDF'),
                ),
              ],
            ),
          ),

          if (_isBannerLoaded && _bannerAd != null)
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
    );
  }
}
