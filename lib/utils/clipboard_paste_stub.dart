/// Stub non-web (Android/iOS/desktop) — paste gambar dari clipboard lewat
/// event browser tidak berlaku di platform ini.
void listenForImagePaste(void Function(String name, List<int> bytes) onImage) {}

void stopListeningForImagePaste() {}
