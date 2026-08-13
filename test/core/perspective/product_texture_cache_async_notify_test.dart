library;

import 'package:flutter_test/flutter_test.dart';

import 'package:staff_decor_studio/core/perspective/product_texture_cache.dart';

void main() {
  test(
    'ProductTextureCache.ensureLoading ne notifie jamais de facon '
    'SYNCHRONE, meme si _load leve avant son premier await (ex: URL '
    'syntaxiquement malformee, non vide -> Uri.parse leve une '
    'FormatException dans le prefixe pre-await de _load). '
    'notifyListeners() ne doit arriver qu apres une microtache, jamais '
    'dans la pile d appel de ensureLoading (qui peut etre invoque depuis '
    'paint(), ou markNeedsPaint() pendant debugDoingPaint est interdit).',
    () async {
      // Ref unique pour ne pas polluer _failed d'un autre test partageant
      // le meme singleton ProductTextureCache.instance.
      const ref = '__test_async_notify_probe_malformed_url__';

      var notified = false;
      void cb() => notified = true;

      ProductTextureCache.instance.addListener(cb);

      // URL non vide (ne declenche donc PAS le garde url.isEmpty existant)
      // mais syntaxiquement invalide : Uri.parse leve une FormatException
      // AVANT le premier await de _load (confirme par lecture: la seule
      // instruction du prefixe pre-await est `Uri.parse(url)` dans
      // `http.get(Uri.parse(url))`).
      ProductTextureCache.instance.ensureLoading(ref, 'http://[invalide');

      // Assertion cle : au retour SYNCHRONE de ensureLoading, le listener
      // ne doit PAS avoir ete appele. Si _load notifie de facon synchrone
      // (throw synchrone -> catch synchrone -> notifyListeners()
      // synchrone), cette assertion echoue.
      expect(
        notified,
        isFalse,
        reason:
            'notifyListeners() a ete appele de facon SYNCHRONE, dans la '
            'meme pile d appel que ensureLoading — dangereux si '
            'ensureLoading est invoque depuis paint() (markNeedsPaint '
            'pendant debugDoingPaint).',
      );

      // Apres une microtache, le listener doit avoir ete notifie (le
      // chemin d'echec fonctionne toujours, juste de facon asynchrone).
      await Future<void>.microtask(() {});
      expect(notified, isTrue);

      ProductTextureCache.instance.removeListener(cb);
    },
  );
}
