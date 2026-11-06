# Changelog

Todas as alterações notáveis neste projeto serão documentadas neste arquivo.

O formato é baseado no [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/),
e este projeto adere ao [Semantic Versioning](https://semver.org/lang/pt-BR/).

---

## [1.1.0] - 2026-11-06

### Adicionado
- **Navegador Web Integrado (`BrowserTab`)**:
  - Navegue em qualquer site diretamente pelo app e detecte mídias reproduzidas para download com 1 clique.
- **Seletor Avançado de Formatos (`MediaFormatSelectorDialog`)**:
  - Escolha entre múltiplos fluxos de áudio e vídeo, resoluções (1080p, 720p, 480p, etc.) e taxas de bits antes de iniciar o download.
- **Detector Automático de Mídia (`MediaDetectorService`)**:
  - Reconhecimento automático de links diretos de mídia, serviços de streaming, animes e YouTube.
- **Aba de Conversão Local de Mídia**:
  - Converte arquivos já salvos no computador para formatos como MP3, AAC, FLAC, WAV, OGG, MP4, MKV e AVI com ajuste de bitrate e monitoramento em tempo real do progresso via FFmpeg.
- **Console de Logs e Diagnóstico (`LogViewerDialog`)**:
  - Histórico de eventos, avisos e erros em tempo real com contador dinâmico na AppBar e suporte para copiar e exportar diagnósticos.
- **Download Multithread com Chunks**:
  - Motor de download de alto desempenho com suporte a múltiplos chunks simultâneos, reconexão automática e controle preciso de pausa/retomada.
- **Diálogo Sobre o Projeto**:
  - Exibição de informações do aplicativo, versão e desenvolvedor (**Gabriel Moreno Medeiros**).
- **Documentação Abrangente**:
  - README completo, guia de arquitetura (`docs/ARQUITETURA.md`) e guia de uso (`docs/GUIA_USO.md`).

### Modificado
- Reformulação visual da interface com Material 3, tema dinâmico claro/escuro e suporte a telas compactas e desktop.
- Integração refinada do FFmpeg com validação de binários no sistema e feedback visual claro de disponibilidade.

---

## [1.0.0] - 2026-11-06

### Adicionado
- Versão inicial do **Download Fácil**.
- Suporte a download de arquivos via HTTP/HTTPS com Dio.
- Integração preliminar com `youtube_explode_dart`.
- Seleção de diretório de destino local com `file_picker` e `path_provider`.
- Interface inicial com cards de status de download (pendente, baixando, pausado, concluído, erro).

