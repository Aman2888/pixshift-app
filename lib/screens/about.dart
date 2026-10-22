import 'package:flutter/material.dart';
import '../theme.dart';
import '../ui/logo.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Widget _perm(String icon, String title, String text, String status, {bool used = false}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.lineSoft)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 40, height: 40, alignment: Alignment.center, decoration: BoxDecoration(color: C.brand50, borderRadius: BorderRadius.circular(12)), child: Text(icon, style: const TextStyle(fontSize: 20))),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title, style: body(15, w: FontWeight.w800))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: used ? C.zest : C.lineSoft, borderRadius: BorderRadius.circular(999)),
                  child: Text(status, style: body(11, w: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 4),
              Text(text, style: body(13, color: C.ink2, h: 1.35)),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 20, 16, 24), children: [
          // Header block: fills the top of the page with the app identity.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: C.pine,
              gradient: const RadialGradient(center: Alignment(0.0, -1.2), radius: 1.3, colors: [Color(0x55C8F23A), C.pine]),
            ),
            child: Column(children: [
              const PixLogo(size: 76),
              const SizedBox(height: 14),
              Text('About PixShift', style: display(28, color: Colors.white), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('Free image tools. Private by design.', style: body(14, color: Colors.white70), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: C.zest, borderRadius: BorderRadius.circular(999)),
                child: Text('Version 1.0.0', style: body(12, w: FontWeight.w800)),
              ),
            ]),
          ),
          const SizedBox(height: 22),
          Text('What PixShift is', style: display(22)),
          const SizedBox(height: 8),
          Text('PixShift is a free set of 89 image tools: compress, resize, convert, crop, edit, make PDFs, collages and more. Every tool works on your phone. Your pictures are never uploaded to a server and there is no sign-up.', style: body(15, color: C.ink2, h: 1.45)),
          const SizedBox(height: 22),
          Text('Privacy and permissions', style: display(22)),
          const SizedBox(height: 6),
          Text('Here is exactly what the app can access.', style: body(14, color: C.muted)),
          const SizedBox(height: 12),
          _perm('🖼️', 'Photos and files', 'Only the pictures you pick yourself, through the Android picker. The app cannot browse your gallery or other files.', 'Only what you pick', used: true),
          _perm('💾', 'Saving results', 'Files are saved only when you tap Save, Gallery or Share. On older Android versions (9 and below) the phone may ask for storage permission for the Gallery button.', 'When you tap', used: true),
          _perm('🌐', 'Internet', 'Used only to download the app\'s text fonts. Your pictures are never sent anywhere.', 'Fonts only', used: true),
          _perm('📷', 'Camera', 'Not used.', 'Not used'),
          _perm('🎤', 'Microphone', 'Not used.', 'Not used'),
          _perm('📍', 'Location', 'Not used. The EXIF tool only reads location data inside your photo, on your phone, so you can remove it.', 'Not used'),
          _perm('👤', 'Contacts, calls and SMS', 'Not used.', 'Not used'),
          const SizedBox(height: 14),
          Text('Your data', style: display(22)),
          const SizedBox(height: 8),
          Text('Your photos stay on your device. PixShift does not collect, store or share your images or any personal information, and it has no accounts, ads or tracking.', style: body(15, color: C.ink2, h: 1.45)),
          const SizedBox(height: 22),
          Text('Honest limits', style: display(22)),
          const SizedBox(height: 8),
          Text('The background remover and changer are colour based (they work best on plain backgrounds). The upscaler enlarges by smooth scaling plus sharpening. Object removal fills from surrounding pixels. None of these use AI generation.', style: body(15, color: C.ink2, h: 1.45)),
        ]),
      );
}
