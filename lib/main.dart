import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  runApp(const MyApp());
}

// ======================================================
// APP
// ======================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PDF AI Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const PdfChunkScreen(),
    );
  }
}

// ======================================================
// SCREEN
// ======================================================

class PdfChunkScreen extends StatefulWidget {
  const PdfChunkScreen({super.key});

  @override
  State<PdfChunkScreen> createState() => _PdfChunkScreenState();
}

class _PdfChunkScreenState extends State<PdfChunkScreen> {
  // ======================================================
  // GEMINI MODEL
  // ======================================================

  late GenerativeModel model;

  // PUT YOUR GEMINI API KEY HERE
  final String apiKey = "AIzaSyC7P8c8ItqGTgCl0xVgkd_2x3eIuZ2Y7t8";

  bool isModelInitialized = false;

  String modelError = '';

  // ======================================================
  // STATES
  // ======================================================

  List<String> chunks = [];

  bool isLoading = false;

  double progress = 0;

  String currentStep = '';

  String aiAnswer = '';

  final TextEditingController questionController = TextEditingController();
  
  final ScrollController _aiScrollController = ScrollController();
  final ScrollController _chunksScrollController = ScrollController();

  // ======================================================
  // INIT
  // ======================================================

  @override
  void initState() {
    super.initState();
    initializeModel();
  }

  @override
  void dispose() {
    _aiScrollController.dispose();
    _chunksScrollController.dispose();
    questionController.dispose();
    super.dispose();
  }

  // ======================================================
  // INITIALIZE GEMINI
  // ======================================================

  Future<void> initializeModel() async {
    try {
      // Try different model names
      List<String> modelNames = [
        "gemini-3-flash-preview"
    
      ];
      
      bool initialized = false;
      
      for (String modelName in modelNames) {
        try {
          final testModel = GenerativeModel(
            model: modelName,
            apiKey: apiKey,
          );
          
          // Test the model
          await testModel.generateContent([
            Content.text("test")
          ]);
          
          setState(() {
            model = testModel;
            isModelInitialized = true;
            modelError = '';
          });
          
          debugPrint("✅ GEMINI INITIALIZED with: $modelName");
          initialized = true;
          break;
        } catch (e) {
          debugPrint("❌ Failed with $modelName: $e");
          continue;
        }
      }
      
      if (!initialized) {
        setState(() {
          isModelInitialized = false;
          modelError = 'Failed to initialize any model. Please check your API key.';
        });
      }
    } catch (e) {
      debugPrint("❌ GEMINI ERROR: $e");

      setState(() {
        isModelInitialized = false;
        modelError = e.toString();
      });
    }
  }

  // ======================================================
  // PICK PDF
  // ======================================================

  Future<void> pickPdf() async {
    try {
      setState(() {
        isLoading = true;
        progress = 0;
        currentStep = "Picking PDF...";
        chunks.clear();
        aiAnswer = '';
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,
      );

      if (result == null) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      final bytes = result.files.first.bytes;

      if (bytes == null) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      // ======================================================
      // READ PDF
      // ======================================================

      setState(() {
        currentStep = "Reading PDF...";
        progress = 0.1;
      });

      final document = PdfDocument(
        inputBytes: bytes,
      );

      final extractor = PdfTextExtractor(document);

      String fullText = '';

      final totalPages = document.pages.count;

      for (int i = 0; i < totalPages; i++) {
        final text = extractor.extractText(
          startPageIndex: i,
          endPageIndex: i,
        );

        fullText += '\n$text';

        setState(() {
          currentStep = "Extracting page ${i + 1}/$totalPages";
          progress = ((i + 1) / totalPages) * 0.6;
        });

        await Future.delayed(
          const Duration(milliseconds: 20),
        );
      }

      document.dispose();

      // ======================================================
      // CHUNKING
      // ======================================================

      setState(() {
        currentStep = "Chunking PDF...";
        progress = 0.7;
      });

      final generatedChunks = await chunkText(fullText);

      setState(() {
        chunks = generatedChunks;
        progress = 1.0;
        currentStep = "Completed";
        isLoading = false;
      });

      debugPrint("TOTAL CHUNKS: ${chunks.length}");
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ PDF Loaded! ${chunks.length} chunks created"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint("PDF ERROR: $e");

      setState(() {
        isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ======================================================
  // CHUNK TEXT
  // ======================================================

  Future<List<String>> chunkText(String text) async {
    const int chunkSize = 500;

    final words = text.split(RegExp(r'\s+'));

    List<String> result = [];

    final totalWords = words.length;

    for (int i = 0; i < totalWords; i += chunkSize) {
      final end = (i + chunkSize < totalWords) ? i + chunkSize : totalWords;

      final chunk = words.sublist(i, end).join(' ');

      result.add(chunk);

      final chunkProgress = i / totalWords;

      setState(() {
        progress = 0.7 + (chunkProgress * 0.3);
        currentStep = "Creating chunk ${result.length}";
      });

      await Future.delayed(const Duration(milliseconds: 10));
    }

    return result;
  }

  // ======================================================
  // NORMALIZE TEXT
  // ======================================================

  String normalizeText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ======================================================
  // IMPROVED SEARCH
  // ======================================================

  List<String> searchChunks(String question) {
    final q = normalizeText(question);
    final questionWords = q.split(RegExp(r'\s+'));

    List<Map<String, dynamic>> scoredChunks = [];

    for (final chunk in chunks) {
      final chunkLower = normalizeText(chunk);

      int score = 0;

      // exact match
      if (chunkLower.contains(q)) {
        score += 100;
      }

      // word matching
      for (final word in questionWords) {
        if (word.isEmpty) continue;
        if (word.length <= 1) continue;
        if (chunkLower.contains(word)) {
          score += 10;
        }
      }

      // bonus for longer words
      for (final word in questionWords) {
        if (word.length >= 3 && chunkLower.contains(word)) {
          score += 5;
        }
      }

      if (score > 0) {
        scoredChunks.add({
          'chunk': chunk,
          'score': score,
        });
      }
    }

    // sort
    scoredChunks.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    debugPrint("FOUND CHUNKS: ${scoredChunks.length}");

    return scoredChunks.take(5).map((e) => e['chunk'] as String).toList();
  }

  // ======================================================
  // ASK AI
  // ======================================================

  Future<void> askQuestion() async {
    final question = questionController.text.trim();

    if (question.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter a question")),
      );
      return;
    }

    if (!isModelInitialized) {
      setState(() {
        aiAnswer = "❌ Model not initialized.\n$modelError";
      });
      return;
    }

    if (chunks.isEmpty) {
      setState(() {
        aiAnswer = "❌ Upload PDF first.";
      });
      return;
    }

    setState(() {
      aiAnswer = "🤔 Thinking...";
    });

    // ======================================================
    // SEARCH RELEVANT CHUNKS
    // ======================================================

    List<String> matchedChunks = searchChunks(question);

    // fallback
    if (matchedChunks.isEmpty) {
      debugPrint("⚠️ NO MATCHES. USING FALLBACK.");
      matchedChunks = chunks.take(3).toList();
    }

    final pdfContext = matchedChunks.join("\n\n---\n\n");

    // ======================================================
    // PROMPT
    // ======================================================

    final prompt = """
You are a PDF assistant.

Rules:
1. ONLY answer using PDF content.
2. If answer not found say: "Answer not found in PDF."
3. Keep answers simple and clear.

PDF CONTENT:
$pdfContext

QUESTION:
$question

ANSWER:
""";

    try {
      final response = await model.generateContent([
        Content.text(prompt),
      ]);

      setState(() {
        aiAnswer = response.text ?? "No response";
      });
      
      // Auto-scroll to AI answer
      Future.delayed(const Duration(milliseconds: 100), () {
        _aiScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });

      debugPrint("✅ AI RESPONSE RECEIVED");
    } catch (e) {
      debugPrint("AI ERROR: $e");

      setState(() {
        aiAnswer = "❌ AI ERROR:\n$e";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("AI Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // ======================================================
  // UI
  // ======================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("PDF AI Assistant"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (chunks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Chip(
                label: Text("${chunks.length} chunks", style: const TextStyle(color: Colors.white)),
                backgroundColor: Colors.white24,
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // ======================================================
          // TOP SECTION (PDF Upload & Loading)
          // ======================================================
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Column(
              children: [
                // Model Error
                if (!isModelInitialized)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "⚠️ $modelError",
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                
                // Upload Button
                ElevatedButton.icon(
                  onPressed: isLoading ? null : pickPdf,
                  icon: const Icon(Icons.upload_file),
                  label: const Text("Upload PDF"),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Loading Progress
                if (isLoading)
                  Column(
                    children: [
                      LinearProgressIndicator(
                        value: progress,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "${(progress * 100).toStringAsFixed(0)}%",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(currentStep, style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
              ],
            ),
          ),
          
          // ======================================================
          // QUESTION & AI ANSWER SECTION (Scrollable)
          // ======================================================
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              controller: _aiScrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Question Input
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.shade200,
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: questionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.blue, width: 2),
                        ),
                        hintText: "Ask a question about your PDF...",
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        prefixIcon: const Icon(Icons.question_answer, color: Colors.blue),
                        contentPadding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Ask Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (chunks.isEmpty || isLoading) ? null : askQuestion,
                      icon: const Icon(Icons.send),
                      label: const Text("Ask AI", style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // AI Answer
                  if (aiAnswer.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.blue.shade50,
                            Colors.purple.shade50,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(Icons.auto_awesome, color: Colors.blue, size: 20),
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                "AI Answer",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SelectableText(
                            aiAnswer,
                            style: const TextStyle(fontSize: 16, height: 1.5),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          
          // ======================================================
          // CHUNK PREVIEW SECTION (Scrollable)
          // ======================================================
          if (chunks.isNotEmpty)
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    border: Border(
                      top: BorderSide(color: Colors.grey.shade300),
                      bottom: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.preview, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            "PDF Content Preview",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "${chunks.length} chunks",
                        style: TextStyle(
                          color: Colors.blue.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 200, // Fixed height for chunks preview
                  child: ListView.builder(
                    controller: _chunksScrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: chunks.length,
                    itemBuilder: (context, index) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: Text(
                              "${index + 1}",
                              style: TextStyle(color: Colors.blue.shade700),
                            ),
                          ),
                          title: Text(
                            "Chunk ${index + 1}",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            chunks[index],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: SelectableText(
                                chunks[index],
                                style: const TextStyle(fontSize: 14, height: 1.4),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
        ],
      ),
      floatingActionButton: chunks.isNotEmpty && aiAnswer.isNotEmpty
          ? FloatingActionButton.small(
              onPressed: () {
                _aiScrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              },
              child: const Icon(Icons.arrow_upward),
            )
          : null,
    );
  }
}