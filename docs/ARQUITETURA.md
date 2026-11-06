# 🏛️ Documentação de Arquitetura - Download Fácil

**Desenvolvedor:** Gabriel Moreno Medeiros  
**Versão da Aplicação:** 1.1.0  
**Stack Principal:** Flutter, Dart, Dio, FFmpeg, youtube_explode_dart  

---

## 1. Visão Geral do Sistema

O **Download Fácil** foi projetado seguindo princípios de alta coesão, baixo acoplamento e separação de responsabilidades. A aplicação provê uma experiência integrada para gerenciar transferências de rede concorrentes com segmentação de chunks, conversão de formatos de áudio/vídeo e navegação com detecção de fluxos multimídia.

```
+-------------------------------------------------------------+
|                  Camada de Apresentação                     |
|  - HomePage (Abas: Downloads, Navegador Web, Conversor)     |
|  - Dialogs (Seletor de Formatos, Conversor, Console de Logs)|
|  - Cards Reativos (DownloadCard, ConversionCard, etc.)      |
+------------------------------+------------------------------+
                               |
                               v
+-------------------------------------------------------------+
|               Camada de Serviços & Domínio                  |
|  - MediaDetectorService (Sniffing e análise de URLs)        |
|  - YouTubeService (Extração de streams e metadados)         |
|  - FFmpegService (Manipulação de processos locais de mídia) |
|  - LogService (Captura de diagnósticos e observabilidade)   |
|  - StorageResolver (Resolução de sistema de arquivos)       |
+------------------------------+------------------------------+
                               |
                               v
+-------------------------------------------------------------+
|               Camada de Motores (Engines)                   |
|  - DownloadEngine (Fachada abstrata de download)            |
|    ├── IODownloadEngine (Desktop / Mobile: Chunks, Dio)     |
|    └── WebDownloadEngine (Web: Blobs, Âncoras HTML5)        |
+-------------------------------------------------------------+
```

---

## 2. Motor de Download (Download Engine)

O motor de download foi concebido com uma estratégia de isolamento de plataforma:

### 2.1 Interface Unificada (`DownloadEngine`)
Define os contratos para:
- `start(DownloadItem item)`
- `pause(DownloadItem item)`
- `resume(DownloadItem item)`
- `cancel(DownloadItem item)`

### 2.2 Motor Nativo (`IODownloadEngine`)
Para plataformas desktop (Linux, Windows, macOS) e mobile:
1. **Inspeção de Cabeçalhos (HEAD Request)**:
   - Verifica o tamanho do arquivo via `Content-Length`.
   - Verifica suporte a fatiamento paralelo via `Accept-Ranges: bytes`.
2. **Download Multithread por Segmentos (Chunks)**:
   - Quando suportado, o arquivo é dividido em partes (por padrão 4 conexões simultâneas).
   - Cada parte envia cabeçalhos HTTP como `Range: bytes=start-end`.
   - Os chunks gravam seus bytes temporários em arquivos `.partN` com verificação de integridade.
3. **Mapeamento e Montagem Final**:
   - Assim que todos os segmentos atingem 100%, os arquivos parciais são combinados sequencialmente no arquivo final (`RandomAccessFile` em stream).
4. **Resiliente e Sem Perda de Estado**:
   - O item armazena o status, bytes baixados e total de bytes, permitindo que pausas preservem o progresso dos chunks.
5. **Cálculo de Telemetria**:
   - Uma janela temporal móvel calcula a velocidade média (`bytes / tempo`) e projeta o ETA (tempo estimado de conclusão).

### 2.3 Motor Web (`WebDownloadEngine`)
- Lida com as restrições de sandbox dos navegadores modernos, disparando downloads usando a API do navegador via `Blob` e links simulados com atributo `download`.

---

## 3. Detecção e Extração de Mídia (`MediaDetectorService`)

O serviço inspeciona a URL fornecida pelo usuário ou interceptada no navegador:
1. **Detecção de YouTube**:
   - Valida URLs `youtube.com` ou `youtu.be`.
   - Utiliza `youtube_explode_dart` para obter árvore completa de manifestos de vídeo e áudio.
   - Lista opções de resolução (144p até 1080p/4K) e extração de áudio puro (MP3/AAC).
2. **Detecção de Links Diretos & Streaming**:
   - Executa pré-checagem HTTP com `User-Agent` adequado para identificar `Content-Type` de vídeo/áudio ou streams HLS (.m3u8).
   - Extrai metadados de nome de arquivo, thumbnail e tamanho prévio.

---

## 4. Integração com FFmpeg (`FFmpegService`)

O `FFmpegService` atua como uma ponte assíncrona para o utilitário de linha de comando `ffmpeg`:
- **Verificação Dinâmica**: Checa se o binário está no `PATH` do sistema operacional.
- **Muxing (Multiplexação)**: Em vídeos de alta resolução onde o YouTube separa os canais de áudio e vídeo, o serviço faz o download de ambos e os funde de forma transparente sem perda de qualidade (`-c:v copy -c:a aac`).
- **Conversão de Formatos**: Transcodifica arquivos locais ou recém-baixados com suporte a seleção de codec, container e bitrate de áudio (`-b:a 192k`).
- **Parser de Progresso**: Monitora a saída `stderr` do FFmpeg em tempo real, calculando a porcentagem de conversão a partir das strings `time=HH:MM:SS.ms`.

---

## 5. Console de Diagnóstico e Observabilidade (`LogService`)

- **Captura Global de Erros**: Configurado no `main()` via `FlutterError.onError` e `PlatformDispatcher.instance.onError`.
- **Níveis de Log**: `INFO`, `WARNING`, `ERROR`.
- **Notificação Reativa**: Um `ValueNotifier<int>` monitora o total de falhas na sessão, atualizando instantaneamente o Badge numérico no AppBar da interface.
- **Exportação**: Suporte para cópia do buffer de logs para a área de transferência do sistema para depuração.

---

## 6. Autoria e Direitos

Projeto concebido e desenvolvido por **Gabriel Moreno Medeiros**.  
Licenciado sob a Licença MIT.
