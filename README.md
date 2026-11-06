# ⚡ Download Fácil

[![Flutter](https://img.shields.io/badge/Flutter-3.13%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.1%2B-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Versão](https://img.shields.io/badge/Versão-1.1.0-brightgreen.svg)](CHANGELOG.md)
[![Licença: MIT](https://img.shields.io/badge/Licen%C3%A7a-MIT-yellow.svg)](LICENSE)
[![Autor](https://img.shields.io/badge/Desenvolvedor-Gabriel%20Moreno%20Medeiros-blue.svg)](#-desenvolvedor)

> **Download Fácil** é um aplicativo moderno, rápido e intuitivo desenvolvido em Flutter para gerenciamento avançado de downloads, captura de fluxos de áudio e vídeo da internet, conversão de formatos com FFmpeg e navegação web integrada.

---

## 👨‍💻 Desenvolvedor

- **Nome:** Gabriel Moreno Medeiros
- **Projeto:** Download Fácil
- **Versão:** 1.1.0

---

## ✨ Principais Funcionalidades

### 🚀 Motor de Download de Alta Performance (Multithread)
- **Segmentação em Chunks**: Aceleração de downloads através da divisão de arquivos em múltiplos segmentos paralelos utilizando requisições `Range` HTTP.
- **Pausa e Retomada Confiável**: Capacidade de pausar qualquer download e continuar do ponto exato onde parou sem perda de dados.
- **Métricas em Tempo Real**: Cálculo dinâmico de velocidade de transferência (KB/s, MB/s), tempo estimado restante (ETA) e porcentagem de progresso.
- **Fallback Inteligente**: Se o servidor remoto não suportar chunks (`Accept-Ranges: bytes`), o motor alterna automaticamente para download contínuo resiliente.

### 🎥 Detecção e Extração de Mídia
- **Suporte Abrangente a Vídeos e Músicas**: Extração de fluxos de vídeo (1080p, 720p, 480p, etc.) e áudio de alta fidelidade.
- **Prévia Instantânea de Links**: Análise automática com exibição de thumbnail, canal/autor, título e duração do conteúdo antes do download.
- **Seletor Avançado de Resoluções e Formatos**: Modal interativo que permite ao usuário escolher exatamente a qualidade de vídeo ou formato de áudio desejado (MP4, MKV, WebM, MP3, AAC, FLAC, etc.).
- **Suporte a Mídias Diretas e Streaming**: Reconhecimento de URLs diretas, listas HLS/m3u8 e players de sites populares.

### 🌐 Navegador Web Integrado
- **Aba de Navegação Embutida**: Navegue em websites e portais de vídeos diretamente dentro do aplicativo.
- **Sniffer de Mídia Automático**: Detecta mídias reproduzidas na página atual e oferece um botão direto para enviar a mídia para o gerenciador de downloads.

### 🔄 Conversor de Mídia Local (FFmpeg)
- **Conversão Offline**: Converta arquivos de áudio e vídeo já salvos no seu computador.
- **Formatos Suportados**:
  - Áudio: MP3, AAC, FLAC, WAV, OGG, M4A.
  - Vídeo: MP4, MKV, AVI, MOV, WEBM.
- **Controle de Taxa de Bits (Bitrate)**: Opções de 128k, 192k, 256k e 320k para áudio.
- **Monitoramento de Conversão**: Acompanhamento de progresso de conversão através da análise da saída em tempo real do processo do FFmpeg.

### 🩺 Console de Diagnóstico & Logs
- **Terminal de Diagnóstico Integrado**: Botão na barra de navegação com contador dinâmico de erros.
- **Histórico Completo**: Visualização filtrável de logs com níveis `INFO`, `WARNING` e `ERROR`.
- **Exportação de Diagnóstico**: Opções para copiar todo o histórico ou limpar os registros para depuração.

---

## 🏗️ Arquitetura do Software

O projeto é estruturado seguindo os princípios de separação de responsabilidades e código limpo (*Clean Architecture*):

```
lib/
├── main.dart                          # Ponto de entrada da aplicação
├── models/                            # Modelos de dados imutáveis
│   ├── conversion_item.dart           # Estado e metadados de conversão
│   ├── download_item.dart             # Estado, chunks, progresso e metadados de download
│   ├── log_entry.dart                 # Registro estruturado de logs do sistema
│   └── media_format_option.dart       # Opções de qualidade/formato de mídia
├── services/                          # Serviços de infraestrutura e lógica de negócio
│   ├── engine/                        # Motores de download especializados
│   │   ├── download_engine.dart       # Interface/fachada única de download
│   │   ├── io_download_engine.dart    # Implementação multithread nativa para Desktop/Mobile
│   │   └── web_download_engine.dart   # Implementação compatível com navegadores Web
│   ├── ffmpeg_service.dart            # Wrapper de execução de comandos FFmpeg locais
│   ├── log_service.dart               # Sistema de telemetria, captura global de erros e logs
│   ├── media_detector_service.dart    # Detecção e inspeção de URLs de vídeo/áudio
│   ├── storage_resolver.dart          # Resolução segura de caminhos de arquivos em disco
│   └── youtube_service.dart           # Extração de streams e metadados do YouTube
└── ui/                                # Camada de apresentação (Interface do Usuário)
    ├── home_page.dart                 # Tela principal com abas e controle de estado
    ├── dialogs/                       # Modais interativos
    │   ├── convert_media_dialog.dart
    │   └── media_format_selector_dialog.dart
    └── widgets/                       # Componentes reutilizáveis
        ├── browser_tab.dart           # Navegador web com detecção de mídia
        ├── conversion_card.dart       # Card de item sendo convertido
        ├── download_card.dart         # Card de download com barra de progresso, botões de ação e status
        ├── ffmpeg_status_card.dart    # Card de disponibilidade do FFmpeg
        ├── local_conversion_card.dart # Painel de seleção de arquivo local e conversão
        ├── log_viewer_dialog.dart     # Modal de console de terminal de logs
        └── url_input_card.dart        # Campo de entrada de URL com debounce e prévia
```

Para detalhes aprofundados sobre os fluxos e decisões de design, consulte [docs/ARQUITETURA.md](docs/ARQUITETURA.md).

---

## 💻 Requisitos do Sistema

- **Flutter SDK**: `>= 3.13.2`
- **Dart SDK**: `>= 3.1.0`
- **Sistemas Operacionais Suportados**:
  - Linux (Ubuntu, Debian, Fedora, Arch Linux, etc.)
  - Windows 10/11
  - macOS
  - Navegadores Web (Chrome, Firefox, Edge)
  - Android
- **FFmpeg (Opcional, altamente recomendado)**:
  - Necessário para mesclagem de vídeos em alta resolução e conversão de formatos de mídia.

### Instalando o FFmpeg no seu Sistema

#### Linux (Debian / Ubuntu):
```bash
sudo apt update && sudo apt install ffmpeg
```

#### Linux (Arch Linux):
```bash
sudo pacman -S ffmpeg
```

#### Windows:
Instale via [winget](https://learn.microsoft.com/windows/package-manager/winget/):
```powershell
winget install Gyan.FFmpeg
```
*Certifique-se de que o diretório `bin` do FFmpeg está adicionado às Variáveis de Ambiente (`PATH`).*

#### macOS:
```bash
brew install ffmpeg
```

---

## 🚀 Como Executar o Projeto

1. **Clone o repositório:**
   ```bash
   git clone https://github.com/medasdev/download_facil.git
   cd download_facil
   ```

2. **Obtenha as dependências:**
   ```bash
   flutter pub get
   ```

3. **Execute na plataforma desejada:**

   - **Linux Desktop:**
     ```bash
     flutter run -d linux
     ```

   - **Windows Desktop:**
     ```bash
     flutter run -d windows
     ```

   - **macOS Desktop:**
     ```bash
     flutter run -d macos
     ```

   - **Navegador Web:**
     ```bash
     flutter run -d chrome
     ```

---

## 📦 Como Gerar a Versão de Produção (Build)

- **Linux:**
  ```bash
  flutter build linux --release
  ```
  O binário executável será gerado em `build/linux/x64/release/bundle/download_facil`.

- **Windows:**
  ```bash
  flutter build windows --release
  ```
  Os arquivos executáveis estarão em `build/windows/x64/runner/Release/`.

- **Android (APK):**
  ```bash
  flutter build apk --release
  ```

---

## 🧪 Testes Automatizados

O projeto conta com bateria de testes unitários e de integração para validar motores de download, manipulação de URLs, extração e diagnóstico:

```bash
flutter test
```

---

## 📌 Versionamento

Este projeto adota o padrão de [Versionamento Semântico 2.0.0 (SemVer)](https://semver.org/lang/pt-BR/).
As versões são estruturadas em `MAJOR.MINOR.PATCH`:

- **MAJOR**: Alterações incompatíveis de API ou arquitetura.
- **MINOR**: Novas funcionalidades adicionadas de maneira retrocompatível.
- **PATCH**: Correções de bugs retrocompatíveis.

Para o histórico completo de lançamentos e notas de versão, veja o arquivo [CHANGELOG.md](CHANGELOG.md).

---

## 📄 Licença

Distribuído sob a licença **MIT**. Consulte o arquivo [LICENSE](LICENSE) para obter mais informações.

Copyright (c) 2026 **Gabriel Moreno Medeiros**.
