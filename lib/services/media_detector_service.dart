import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../models/media_format_option.dart';
import 'log_service.dart';
import 'youtube_service.dart';

class MediaDetectorService {
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
      'Accept-Language': 'pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7',
    },
  ));

  /// Identifica se a URL é diretamente um arquivo de mídia
  static bool isDirectMediaUrl(String url) {
    final clean = url.trim().toLowerCase().split('?').first;
    const mediaExts = [
      '.mp4', '.mkv', '.webm', '.avi', '.mov', '.flv',
      '.mp3', '.m4a', '.wav', '.aac', '.ogg', '.flac', '.opus',
      '.m3u8', '.mpd'
    ];
    return mediaExts.any((ext) => clean.endsWith(ext));
  }

  /// Identifica se a URL é de player do Blogger
  static bool isBloggerUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('blogger.com/video.g') || lower.contains('blogger.com/video-redirect.g');
  }

  /// Limpa títulos removendo sufixos promocionais comuns de sites de animes e filmes
  static String cleanTitle(String rawTitle) {
    var title = rawTitle.trim();
    // Remove tags HTML se houver
    title = title.replaceAll(RegExp(r'<[^>]+>'), '');
    // Decodifica entidades HTML comuns
    title = title
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#8211;', '-')
        .replaceAll('&#8212;', '-')
        .replaceAll('&#038;', '&')
        .replaceAll('&nbsp;', ' ');

    // Remove sufixos de sites conhecidos
    final siteSuffixes = [
      RegExp(r'\s*-\s*Animes Online(?:\s*Grátis)?', caseSensitive: false),
      RegExp(r'\s*\|\s*Animes Online', caseSensitive: false),
      RegExp(r'\s*-\s*Assistir.*Online.*$', caseSensitive: false),
      RegExp(r'\s+Online\s*$', caseSensitive: false),
      RegExp(r'\s*-\s*Topflix', caseSensitive: false),
      RegExp(r'\s*-\s*Overflix', caseSensitive: false),
    ];

    for (final suffix in siteSuffixes) {
      title = title.replaceAll(suffix, '');
    }

    title = title.trim();
    return title.isNotEmpty ? title : 'Mídia da Internet';
  }

  /// Detecta mídias (vídeo e áudio) a partir de qualquer URL
  static Future<DetectedMediaInfo?> detectFromUrl(String rawUrl) async {
    final cleanUrl = rawUrl.trim();
    if (cleanUrl.isEmpty) return null;

    // 1. Caso seja YouTube
    if (YouTubeService.isYouTubeUrl(cleanUrl)) {
      LogService.info('Detectando mídia via motor YouTube: $cleanUrl', tag: 'Detector');
      return await YouTubeService.fetchDetectedMedia(cleanUrl);
    }

    // 2. Caso seja link direto de arquivo de mídia
    if (isDirectMediaUrl(cleanUrl)) {
      LogService.info('Link direto de mídia detectado: $cleanUrl', tag: 'Detector');
      return _createDirectMediaInfo(cleanUrl);
    }

    // 3. Caso seja diretamente uma URL do player do Blogger
    if (isBloggerUrl(cleanUrl)) {
      LogService.info('URL direta de player do Blogger detectada: $cleanUrl', tag: 'Detector');
      return await _detectFromBlogger(cleanUrl);
    }

    // 4. Caso seja uma página web HTML comum (animes, filmes, blogs, etc.)
    try {
      LogService.info(
        'Inspecionando página web em busca de players e streams de vídeo/áudio: $cleanUrl',
        tag: 'Detector',
      );
      final response = await _dio.get<String>(
        cleanUrl,
        options: Options(responseType: ResponseType.plain),
      );

      final html = response.data ?? '';
      if (html.isEmpty) {
        return _createGenericUrlMediaInfo(cleanUrl);
      }

      // Extrai título e thumbnail da página
      final title = _extractTitle(html, cleanUrl);
      final thumbnail = _extractThumbnail(html, cleanUrl);

      // 4.1. Busca por iframes do Blogger (usados em massa por sites de animes como animesonlinecc.to)
      final bloggerIframeUrl = _extractBloggerIframe(html, cleanUrl);
      if (bloggerIframeUrl != null) {
        LogService.info('Iframe do Blogger encontrado na página: $bloggerIframeUrl', tag: 'Detector');
        final bloggerMedia = await _detectFromBlogger(
          bloggerIframeUrl,
          parentPageUrl: cleanUrl,
          fallbackTitle: title,
          fallbackThumbnail: thumbnail,
        );
        if (bloggerMedia != null && bloggerMedia.videoFormats.isNotEmpty) {
          LogService.info(
            'Mídia extraída com sucesso do player Blogger para "${bloggerMedia.title}" '
            '(${bloggerMedia.videoFormats.length} opções de vídeo)',
            tag: 'Detector',
          );
          return bloggerMedia;
        }
      }

      // 4.2. Busca por iframes de players DooPlay / DooThemes (WordPress)
      final dooPlayIframes = _extractDooPlayIframes(html, cleanUrl);
      for (final dooUrl in dooPlayIframes) {
        if (isBloggerUrl(dooUrl)) {
          final bloggerMedia = await _detectFromBlogger(
            dooUrl,
            parentPageUrl: cleanUrl,
            fallbackTitle: title,
            fallbackThumbnail: thumbnail,
          );
          if (bloggerMedia != null && bloggerMedia.videoFormats.isNotEmpty) {
            return bloggerMedia;
          }
        }
      }

      // 4.3. Busca por players DooPlay via AJAX se houver indícios na página
      final ajaxDooMedia = await _tryDooPlayAjax(html, cleanUrl, title, thumbnail);
      if (ajaxDooMedia != null) {
        return ajaxDooMedia;
      }

      // 4.4. Sniffing direto no HTML da página atual (<video>, <audio>, <source>, og:video, configs JS)
      final directMedia = sniffHtml(html, cleanUrl, customTitle: title, customThumb: thumbnail);
      if (directMedia != null && directMedia.totalOptionsCount > 0) {
        LogService.info(
          'Mídia detectada na página "${directMedia.title}": '
          '${directMedia.videoFormats.length} vídeo(s), ${directMedia.audioFormats.length} áudio(s)',
          tag: 'Detector',
        );
        return directMedia;
      }

      // 4.5. Inspeciona outros iframes de vídeo embutidos (ex: players de terceiros)
      final candidateIframes = _extractCandidateIframes(html, cleanUrl);
      for (final iframeUrl in candidateIframes.take(3)) {
        try {
          LogService.info('Inspecionando iframe secundário de player: $iframeUrl', tag: 'Detector');
          final iframeResp = await _dio.get<String>(
            iframeUrl,
            options: Options(
              responseType: ResponseType.plain,
              headers: {'Referer': cleanUrl},
            ),
          );
          final iframeHtml = iframeResp.data ?? '';

          // Se o iframe secundário apontar para o Blogger
          if (isBloggerUrl(iframeUrl) || iframeHtml.contains('blogger.com/video')) {
            final bUrl = isBloggerUrl(iframeUrl) ? iframeUrl : _extractBloggerIframe(iframeHtml, iframeUrl);
            if (bUrl != null) {
              final bMedia = await _detectFromBlogger(
                bUrl,
                parentPageUrl: cleanUrl,
                fallbackTitle: title,
                fallbackThumbnail: thumbnail,
              );
              if (bMedia != null && bMedia.videoFormats.isNotEmpty) {
                return bMedia;
              }
            }
          }

          final iframeMedia = sniffHtml(
            iframeHtml,
            iframeUrl,
            customTitle: title,
            customThumb: thumbnail,
            parentReferer: iframeUrl,
          );
          if (iframeMedia != null && iframeMedia.totalOptionsCount > 0) {
            return iframeMedia;
          }
        } catch (e) {
          LogService.warning('Falha ao inspecionar iframe $iframeUrl: $e', tag: 'Detector');
        }
      }

      // Se achou título/thumbnail mas nenhum stream foi extraído, cria opção genérica informada
      return _createGenericUrlMediaInfo(cleanUrl, customTitle: title, customThumbnail: thumbnail);
    } catch (e, stack) {
      LogService.warning(
        'Falha ao inspecionar página HTML: $e',
        tag: 'Detector',
        details: 'URL: $cleanUrl\n$stack',
      );
      return _createGenericUrlMediaInfo(cleanUrl);
    }
  }

  /// Extrai o stream de vídeo diretamente de páginas de player do Blogger
  static Future<DetectedMediaInfo?> _detectFromBlogger(
    String bloggerUrl, {
    String? parentPageUrl,
    String? fallbackTitle,
    String? fallbackThumbnail,
  }) async {
    try {
      LogService.info('Buscando streams do Blogger: $bloggerUrl', tag: 'Detector');
      final resp = await _dio.get<String>(
        bloggerUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: parentPageUrl != null ? {'Referer': parentPageUrl} : null,
        ),
      );
      final rawHtml = resp.data ?? '';
      if (rawHtml.isEmpty) return null;

      // Blogger escapa caracteres unicode em JSON (\u003d para '=', \u0026 para '&', \/ para '/')
      final decodedHtml = rawHtml
          .replaceAll(r'\u003d', '=')
          .replaceAll(r'\u0026', '&')
          .replaceAll(r'\/', '/');

      final videoOptions = <MediaFormatOption>[];
      final audioOptions = <MediaFormatOption>[];
      final seenItags = <String>{};
      Duration? mediaDuration;
      String? bloggerThumb = fallbackThumbnail;

      // Cabeçalhos essenciais para download do GoogleVideo do Blogger (evita 403 Forbidden)
      final bloggerHeaders = <String, String>{
        'Referer': 'https://www.blogger.com/',
        'User-Agent':
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
      };

      void addStreamOption(String streamUrl, String itag) {
        // NUNCA incluir endpoints SABR (sabr=1): são canais binários adaptativos RPC do player
        // interno do YouTube/Blogger e NÃO fornecem o arquivo MP4 diretamente para download.
        if (streamUrl.contains('sabr=1') || streamUrl.contains('sabr%3D1')) {
          LogService.debug('Ignorando endpoint SABR do Blogger: $streamUrl', tag: 'Detector');
          return;
        }

        if (seenItags.contains(itag)) return;
        seenItags.add(itag);

        final clenMatch = RegExp(r'[?&]clen=(\d+)').firstMatch(streamUrl);
        final totalBytes = clenMatch != null ? int.tryParse(clenMatch.group(1)!) : null;

        if (mediaDuration == null) {
          final durMatch = RegExp(r'[?&]dur=([0-9.]+)').firstMatch(streamUrl);
          if (durMatch != null) {
            final secs = double.tryParse(durMatch.group(1)!);
            if (secs != null && secs > 0) {
              mediaDuration = Duration(seconds: secs.round());
            }
          }
        }

        String label;
        String qualityTag;
        String ext = 'mp4';

        switch (itag) {
          case '37':
            label = '1080p (Full HD MP4)';
            qualityTag = '1080p';
            break;
          case '22':
            label = '720p (HD MP4)';
            qualityTag = '720p';
            break;
          case '18':
            label = '360p (SD MP4)';
            qualityTag = '360p';
            break;
          case '13':
            label = '144p (Móvel / 3GPP)';
            qualityTag = '144p';
            ext = '3gp';
            break;
          default:
            label = 'Vídeo MP4 (Original)';
            qualityTag = 'auto';
        }

        videoOptions.add(MediaFormatOption(
          label: label,
          extension: ext,
          category: MediaCategory.video,
          qualityTag: qualityTag,
          totalBytes: totalBytes,
          codecInfo: ext == '3gp' ? 'H.263 / AMR' : 'H.264 / AAC',
          streamId: streamUrl,
          httpHeaders: bloggerHeaders,
        ));
      }

      // 1. Tenta extrair diretamente a partir do objeto oficial VIDEO_CONFIG
      final videoConfigMatch = RegExp(r'VIDEO_CONFIG\s*=\s*(\{.*?\});', dotAll: true).firstMatch(decodedHtml);
      if (videoConfigMatch != null) {
        try {
          final jsonMap = jsonDecode(videoConfigMatch.group(1)!) as Map<String, dynamic>;
          if (jsonMap['thumbnail'] is String && bloggerThumb == null) {
            bloggerThumb = jsonMap['thumbnail'] as String;
          }
          if (jsonMap['streams'] is List) {
            for (final s in jsonMap['streams']) {
              if (s is Map) {
                final playUrl = s['play_url']?.toString();
                final formatId = s['format_id']?.toString() ?? 'auto';
                if (playUrl != null && playUrl.isNotEmpty) {
                  addStreamOption(playUrl, formatId);
                }
              }
            }
          }
        } catch (e) {
          LogService.debug('Falha ao parsear VIDEO_CONFIG do Blogger: $e', tag: 'Detector');
        }
      }

      // 2. Fallback por regex caso o JSON esteja ausente ou não contenha streams válidos
      if (videoOptions.isEmpty) {
        final gvRegex = RegExp(r'''https://[^\s"'<>\\]*googlevideo\.com/videoplayback[^\s"'<>\\]*''');
        final matchedUrls = gvRegex.allMatches(decodedHtml).map((m) => m.group(0)!).toSet();

        for (final streamUrl in matchedUrls) {
          final itagMatch = RegExp(r'[?&]itag=(\d+)').firstMatch(streamUrl);
          final itag = itagMatch?.group(1) ?? 'auto';
          addStreamOption(streamUrl, itag);
        }
      }

      if (videoOptions.isEmpty) {
        LogService.warning('Nenhum stream MP4 válido do googlevideo encontrado no Blogger HTML', tag: 'Detector');
        return null;
      }

      // Ordena resoluções da mais alta para a mais baixa
      videoOptions.sort((a, b) {
        int score(String? q) {
          if (q == '1080p') return 4;
          if (q == '720p') return 3;
          if (q == '360p') return 2;
          if (q == 'auto') return 1;
          return 0;
        }
        return score(b.qualityTag).compareTo(score(a.qualityTag));
      });

      // Opção de extração de áudio MP3
      if (videoOptions.isNotEmpty) {
        audioOptions.add(MediaFormatOption(
          label: 'Extrair Áudio (MP3 - 320 kbps)',
          extension: 'mp3',
          category: MediaCategory.audio,
          qualityTag: '320k',
          codecInfo: 'MP3 LAME',
          streamId: videoOptions.first.streamId,
          httpHeaders: bloggerHeaders,
        ));
      }

      final finalTitle = fallbackTitle?.isNotEmpty == true
          ? fallbackTitle!
          : cleanTitle('Episódio / Vídeo Blogger');

      return DetectedMediaInfo(
        url: parentPageUrl ?? bloggerUrl,
        title: finalTitle,
        thumbnailUrl: bloggerThumb ?? fallbackThumbnail,
        duration: mediaDuration,
        videoFormats: videoOptions,
        audioFormats: audioOptions,
      );
    } catch (e, stack) {
      LogService.warning(
        'Falha ao extrair streams do Blogger: $e',
        tag: 'Detector',
        details: stack.toString(),
      );
      return null;
    }
  }

  /// Tenta resolver requisições DooPlay AJAX para carregar players dinâmicos
  static Future<DetectedMediaInfo?> _tryDooPlayAjax(
    String html,
    String pageUrl,
    String title,
    String? thumb,
  ) async {
    // Procura por data-post, data-nume e data-type (padrão DooPlay / DooThemes)
    final optMatch = RegExp(
      r'''data-post=["'](\d+)["'][^>]*data-nume=["']([^"']+)["'][^>]*data-type=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html) ?? RegExp(
      r'''data-type=["']([^"']+)["'][^>]*data-post=["'](\d+)["'][^>]*data-nume=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);

    if (optMatch == null) return null;

    try {
      final baseUri = Uri.parse(pageUrl);
      final ajaxUrl = '${baseUri.scheme}://${baseUri.host}/wp-admin/admin-ajax.php';

      String post;
      String nume;
      String type;
      if (optMatch.groupCount >= 3 && optMatch.pattern.toString().startsWith('data-post')) {
        post = optMatch.group(1)!;
        nume = optMatch.group(2)!;
        type = optMatch.group(3)!;
      } else {
        type = optMatch.group(1)!;
        post = optMatch.group(2)!;
        nume = optMatch.group(3)!;
      }

      LogService.info('Tentando consulta DooPlay AJAX ($ajaxUrl, post=$post, nume=$nume, type=$type)', tag: 'Detector');
      final resp = await _dio.post<String>(
        ajaxUrl,
        data: {
          'action': 'doo_player_ajax',
          'post': post,
          'nume': nume,
          'type': type,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          headers: {'Referer': pageUrl},
        ),
      );

      final ajaxHtml = resp.data ?? '';
      if (ajaxHtml.isNotEmpty) {
        final bUrl = _extractBloggerIframe(ajaxHtml, pageUrl);
        if (bUrl != null) {
          return await _detectFromBlogger(
            bUrl,
            parentPageUrl: pageUrl,
            fallbackTitle: title,
            fallbackThumbnail: thumb,
          );
        }

        return sniffHtml(ajaxHtml, pageUrl, customTitle: title, customThumb: thumb);
      }
    } catch (_) {}
    return null;
  }

  /// Extrai iframe do Blogger presente no HTML
  static String? _extractBloggerIframe(String html, String baseUrl) {
    final regex = RegExp(
      r'''<iframe[^>]+src=["']([^"']*(?:blogger\.com/video\.g|blogger\.com/video-redirect\.g)[^"']*)["']''',
      caseSensitive: false,
    );
    final match = regex.firstMatch(html);
    if (match != null) {
      return _resolveUrl(baseUrl, match.group(1)!);
    }

    // Busca também em atributos data-src
    final dataSrcRegex = RegExp(
      r'''<iframe[^>]+data-src=["']([^"']*(?:blogger\.com/video\.g|blogger\.com/video-redirect\.g)[^"']*)["']''',
      caseSensitive: false,
    );
    final dataMatch = dataSrcRegex.firstMatch(html);
    if (dataMatch != null) {
      return _resolveUrl(baseUrl, dataMatch.group(1)!);
    }

    return null;
  }

  /// Extrai iframes específicos de players DooThemes / DooPlay (<div class="play-box-iframe">)
  static List<String> _extractDooPlayIframes(String html, String baseUrl) {
    final urls = <String>[];
    final regex = RegExp(
      r'''(?:class=["'][^"']*play-box-iframe[^"']*["'][^>]*>|id=["']option-\d+["'][^>]*>)\s*<iframe[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in regex.allMatches(html)) {
      final src = match.group(1)?.trim();
      if (src != null && src.isNotEmpty) {
        urls.add(_resolveUrl(baseUrl, src));
      }
    }
    return urls;
  }

  /// Extrai todos os iframes que parecem carregar players ou vídeos
  static List<String> _extractCandidateIframes(String html, String baseUrl) {
    final urls = <String>[];
    final iframeRegex = RegExp(
      r'''<iframe[^>]+(?:src|data-src)=["']([^"']+)["']''',
      caseSensitive: false,
    );

    for (final match in iframeRegex.allMatches(html)) {
      final src = match.group(1)?.trim();
      if (src == null || src.isEmpty) continue;
      final lower = src.toLowerCase();

      // Ignora rastreadores, anúncios e widgets sociais
      if (lower.contains('facebook.com') ||
          lower.contains('twitter.com') ||
          lower.contains('disqus.com') ||
          lower.contains('googleads') ||
          lower.contains('recaptcha')) {
        continue;
      }

      urls.add(_resolveUrl(baseUrl, src));
    }
    return urls;
  }

  /// Analisa o conteúdo HTML e extrai mídias embutidas (<video>, <audio>, <source>, og:video, configs JS, etc.)
  static DetectedMediaInfo? sniffHtml(
    String html,
    String pageUrl, {
    String? customTitle,
    String? customThumb,
    String? parentReferer,
  }) {
    if (html.isEmpty) return null;

    final mediaUrls = <String>{};

    // 1. Tags <video src="..."> e <audio src="...">
    final tagRegex = RegExp(
      r'''<(?:video|audio)[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in tagRegex.allMatches(html)) {
      final src = match.group(1)?.trim();
      if (src != null && src.isNotEmpty) mediaUrls.add(src);
    }

    // 2. Tags <source src="...">
    final sourceRegex = RegExp(
      r'''<source[^>]+src=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in sourceRegex.allMatches(html)) {
      final src = match.group(1)?.trim();
      if (src != null && src.isNotEmpty) mediaUrls.add(src);
    }

    // 3. OpenGraph og:video e og:audio
    final ogVideoRegex = RegExp(
      r'''<meta\s+[^>]*property=["']og:video(?:[:\w]+)?["'][^>]*content=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in ogVideoRegex.allMatches(html)) {
      final content = match.group(1)?.trim();
      if (content != null && content.isNotEmpty) mediaUrls.add(content);
    }

    final ogVideoRegexReverse = RegExp(
      r'''<meta\s+[^>]*content=["']([^"']+)["'][^>]*property=["']og:video(?:[:\w]+)?["']''',
      caseSensitive: false,
    );
    for (final match in ogVideoRegexReverse.allMatches(html)) {
      final content = match.group(1)?.trim();
      if (content != null && content.isNotEmpty) mediaUrls.add(content);
    }

    final ogAudioRegex = RegExp(
      r'''<meta\s+[^>]*property=["']og:audio(?:[:\w]+)?["'][^>]*content=["']([^"']+)["']''',
      caseSensitive: false,
    );
    for (final match in ogAudioRegex.allMatches(html)) {
      final content = match.group(1)?.trim();
      if (content != null && content.isNotEmpty) mediaUrls.add(content);
    }

    // 4. Parâmetros de players JavaScript (file: "...", source: "...", url: "...")
    final jsPlayerRegex = RegExp(
      r'''(?:file|source|src|url)\s*:\s*["'](https?://[^"']+\.(?:mp4|webm|m3u8|mpd|mp3|m4a)(?:\?[^"']*)?)["']''',
      caseSensitive: false,
    );
    for (final match in jsPlayerRegex.allMatches(html)) {
      final src = match.group(1)?.trim();
      if (src != null && src.isNotEmpty) mediaUrls.add(src);
    }

    // 5. URLs diretas de mídia no HTML / JSON (.mp4, .webm, .m3u8, .mp3, etc.)
    final urlRegex = RegExp(
      r'''https?://[^\s"'<>\\]+\.(?:mp4|webm|m3u8|mpd|mp3|m4a|wav)(?:\?[^\s"'<>\\]*)?''',
      caseSensitive: false,
    );
    for (final match in urlRegex.allMatches(html)) {
      final found = match.group(0)?.trim();
      if (found != null && found.isNotEmpty) mediaUrls.add(found);
    }

    if (mediaUrls.isEmpty) return null;

    final title = customTitle ?? _extractTitle(html, pageUrl);
    final thumb = customThumb ?? _extractThumbnail(html, pageUrl);

    final videoOptions = <MediaFormatOption>[];
    final audioOptions = <MediaFormatOption>[];

    final customHeaders = parentReferer != null || pageUrl.isNotEmpty
        ? <String, String>{
            'Referer': parentReferer ?? pageUrl,
            'User-Agent':
                'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
          }
        : null;

    for (final rawSrc in mediaUrls) {
      final resolved = _resolveUrl(pageUrl, rawSrc);
      final clean = resolved.toLowerCase().split('?').first;

      final isAudio = clean.endsWith('.mp3') ||
          clean.endsWith('.m4a') ||
          clean.endsWith('.wav') ||
          clean.endsWith('.aac') ||
          clean.endsWith('.ogg');
      final ext = p.extension(clean).replaceFirst('.', '');
      final fileName = p.basename(clean);

      if (isAudio) {
        audioOptions.add(MediaFormatOption(
          label: 'Áudio Original ($fileName)',
          extension: ext.isNotEmpty ? ext : 'mp3',
          category: MediaCategory.audio,
          qualityTag: 'Original',
          streamId: resolved,
          httpHeaders: customHeaders,
        ));
      } else {
        final isHls = clean.endsWith('.m3u8');
        videoOptions.add(MediaFormatOption(
          label: isHls ? 'Transmissão HLS ($fileName)' : 'Vídeo ($fileName)',
          extension: isHls ? 'mp4' : (ext.isNotEmpty ? ext : 'mp4'),
          category: MediaCategory.video,
          qualityTag: isHls ? 'HLS' : 'Original',
          streamId: resolved,
          codecInfo: isHls ? 'HLS Stream' : null,
          httpHeaders: customHeaders,
        ));
      }
    }

    // Se achou vídeo, adiciona opção de extrair áudio em MP3
    if (videoOptions.isNotEmpty && audioOptions.isEmpty) {
      audioOptions.add(MediaFormatOption(
        label: 'Extrair Áudio (MP3 - 320 kbps)',
        extension: 'mp3',
        category: MediaCategory.audio,
        qualityTag: '320k',
        codecInfo: 'MP3 LAME',
        streamId: videoOptions.first.streamId,
        httpHeaders: customHeaders,
      ));
    }

    return DetectedMediaInfo(
      url: pageUrl,
      title: title,
      thumbnailUrl: thumb,
      videoFormats: videoOptions,
      audioFormats: audioOptions,
    );
  }

  static String _extractTitle(String html, String pageUrl) {
    // 1. og:title
    final ogTitle = RegExp(
      r'''<meta\s+[^>]*property=["']og:title["'][^>]*content=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html) ?? RegExp(
      r'''<meta\s+[^>]*content=["']([^"']+)["'][^>]*property=["']og:title["']''',
      caseSensitive: false,
    ).firstMatch(html);

    if (ogTitle != null) {
      final t = ogTitle.group(1)?.trim();
      if (t != null && t.isNotEmpty) return cleanTitle(t);
    }

    // 2. <title>
    final titleMatch = RegExp(r'<title[^>]*>([^<]+)</title>', caseSensitive: false).firstMatch(html);
    if (titleMatch != null) {
      final t = titleMatch.group(1)?.trim();
      if (t != null && t.isNotEmpty) return cleanTitle(t);
    }

    // 3. Fallback a partir do caminho da URL
    try {
      final uri = Uri.parse(pageUrl);
      final lastSegment = uri.pathSegments.lastWhere(
        (s) => s.trim().isNotEmpty,
        orElse: () => '',
      );
      if (lastSegment.isNotEmpty) {
        return cleanTitle(Uri.decodeComponent(lastSegment).replaceAll('-', ' '));
      }
    } catch (_) {}

    return 'Mídia Detectada';
  }

  static String? _extractThumbnail(String html, String pageUrl) {
    final ogImage = RegExp(
      r'''<meta\s+[^>]*property=["']og:image(?::secure_url)?["'][^>]*content=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html) ?? RegExp(
      r'''<meta\s+[^>]*content=["']([^"']+)["'][^>]*property=["']og:image(?::secure_url)?["']''',
      caseSensitive: false,
    ).firstMatch(html);

    if (ogImage != null) {
      return _resolveUrl(pageUrl, ogImage.group(1)?.trim() ?? '');
    }

    final twitterImage = RegExp(
      r'''<meta\s+[^>]*name=["']twitter:image["'][^>]*content=["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(html);
    if (twitterImage != null) {
      return _resolveUrl(pageUrl, twitterImage.group(1)?.trim() ?? '');
    }

    return null;
  }

  static String _resolveUrl(String baseUrl, String relativeOrAbsolute) {
    if (relativeOrAbsolute.startsWith('http://') || relativeOrAbsolute.startsWith('https://')) {
      return relativeOrAbsolute;
    }
    if (relativeOrAbsolute.startsWith('//')) {
      return 'https:$relativeOrAbsolute';
    }
    try {
      final baseUri = Uri.parse(baseUrl);
      final resolved = baseUri.resolve(relativeOrAbsolute);
      return resolved.toString();
    } catch (_) {
      return relativeOrAbsolute;
    }
  }

  static DetectedMediaInfo _createDirectMediaInfo(String url) {
    final uri = Uri.tryParse(url);
    final lastSegment = uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : 'midia';
    final ext = p.extension(lastSegment).replaceFirst('.', '').toLowerCase();
    final nameWithoutExt = p.withoutExtension(lastSegment);

    final isAudio = ['mp3', 'm4a', 'wav', 'aac', 'flac', 'ogg', 'opus'].contains(ext);

    final videoOptions = <MediaFormatOption>[];
    final audioOptions = <MediaFormatOption>[];

    if (isAudio) {
      audioOptions.add(MediaFormatOption(
        label: 'Áudio Original (.${ext.toUpperCase()})',
        extension: ext,
        category: MediaCategory.audio,
        qualityTag: 'Original',
        streamId: url,
      ));
      if (ext != 'mp3') {
        audioOptions.add(const MediaFormatOption(
          label: 'Converter para MP3 (320 kbps)',
          extension: 'mp3',
          category: MediaCategory.audio,
          qualityTag: '320k',
        ));
      }
    } else {
      videoOptions.add(MediaFormatOption(
        label: 'Vídeo Original (.${ext.toUpperCase()})',
        extension: ext.isNotEmpty ? ext : 'mp4',
        category: MediaCategory.video,
        qualityTag: 'Original',
        streamId: url,
      ));
      audioOptions.add(const MediaFormatOption(
        label: 'Extrair Áudio como MP3 (320 kbps)',
        extension: 'mp3',
        category: MediaCategory.audio,
        qualityTag: '320k',
      ));
    }

    return DetectedMediaInfo(
      url: url,
      title: nameWithoutExt.isNotEmpty ? cleanTitle(nameWithoutExt) : 'Mídia da Internet',
      videoFormats: videoOptions,
      audioFormats: audioOptions,
    );
  }

  static DetectedMediaInfo _createGenericUrlMediaInfo(
    String url, {
    String? customTitle,
    String? customThumbnail,
  }) {
    final finalTitle = customTitle ?? _extractTitle('', url);
    return DetectedMediaInfo(
      url: url,
      title: finalTitle,
      thumbnailUrl: customThumbnail,
      videoFormats: [
        MediaFormatOption(
          label: 'Vídeo MP4 (Padrão)',
          extension: 'mp4',
          category: MediaCategory.video,
          qualityTag: 'auto',
          streamId: url,
        ),
      ],
      audioFormats: [
        MediaFormatOption(
          label: 'Áudio MP3 (320 kbps)',
          extension: 'mp3',
          category: MediaCategory.audio,
          qualityTag: '320k',
          streamId: url,
        ),
      ],
    );
  }
}
