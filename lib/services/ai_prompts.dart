// lib/services/ai_prompts.dart

/// Contient tous les prompts pour une langue spécifique.
class LanguagePrompts {
  final String systemChapter;
  final String systemHiragana;
  final String systemRoadmap;
  final String commonInstructions;
  final String firstChapterIntro;
  final String nextChapterIntro;
  final String finalChapterIntro;
  final String finalChapterSpecificInstructions;
  final String contextSectionHeader;
  final String contextLastChapterHeader;
  final String contextSimilarSectionHeader;
  final String contextLastSentenceHeader;
  final String contextFollowInstruction;
  final String outputFormatFirst;
  final String outputFormatNext;
  final String outputFormatFinal;
  final String roadmapUpdatePrompt;
  final String roadmapCreatePrompt;
  final String titleFirst;
  final String titleFinal;
  final String titleChapterPrefix;
  final String titleChapterSuffix;
  final String contextNotAvailable;
  final String firstChapterContext;

  const LanguagePrompts({
    required this.systemChapter,
    required this.systemHiragana,
    required this.systemRoadmap,
    required this.commonInstructions,
    required this.firstChapterIntro,
    required this.nextChapterIntro,
    required this.finalChapterIntro,
    required this.finalChapterSpecificInstructions,
    required this.contextSectionHeader,
    required this.contextLastChapterHeader,
    required this.contextSimilarSectionHeader,
    required this.contextLastSentenceHeader,
    required this.contextFollowInstruction,
    required this.outputFormatFirst,
    required this.outputFormatNext,
    required this.outputFormatFinal,
    required this.roadmapUpdatePrompt,
    required this.roadmapCreatePrompt,
    required this.titleFirst,
    required this.titleFinal,
    required this.titleChapterPrefix,
    required this.titleChapterSuffix,
    required this.contextNotAvailable,
    required this.firstChapterContext,
  });
}

/// Collection centralisée de tous les prompts, organisés par langue.
class AIPrompts {
  static final Map<String, LanguagePrompts> _prompts = {
    'Japonais': _japanesePrompts,
    'Français': _frenchPrompts,
    'Anglais': _englishPrompts,
    'Espagnol': _spanishPrompts,
    'Italien': _italianPrompts,
    'Coréen': _koreanPrompts,
    'default': _englishPrompts, // L'anglais est maintenant la langue par défaut
  };

  /// Récupère le set de prompts pour une langue donnée, ou le set par défaut.
  static LanguagePrompts getPromptsFor(String language) {
    return _prompts[language] ?? _prompts['default']!;
  }
}

// --- SECTIONS DE TEXTE MODULAIRES (PARTAGÉES) ---

const _showDontTellPrinciple = '''
Core Writing Principle - "Show, Don't Tell":
9.  **Do NOT summarize events**. Do not fast-forward the story. Focus on a single, significant scene or a short period of time, rather than trying to cover too much ground in one chapter.
10. **Describe in detail**: Describe the atmosphere of places, characters' facial expressions, and sensory details (smells, sounds, textures).
11. **Depict inner life**: Instead of stating a character's emotion directly (e.g., "He was sad"), **show** it through their actions, thoughts, and dialogue (e.g., "His shoulders slumped, and his gaze remained fixed on the floor.").
12. **Pacing**: **Do not** rush the story. Take time for character psychology and world-building. Lay sufficient groundwork before major events.
13. **Consistency**: Ensure characters' actions are consistent with their established personalities and motivations. Maintain the logical flow of the plot based on the context provided.
''';

// --- PROMPTS PAR LANGUE ---

// Anglais (English)
const _enRules = '''
 Strict rules:
 1.  Write in [NOVEL_LANGUAGE].
 2.  The chapter length should be approximately 3000 characters.
 3.  Maintain consistency with the genre "[NOVEL_GENRE]" and specifications "[NOVEL_SPECIFICATIONS]".
 4.  Make the story engaging and make the reader want to continue reading (except for the final chapter). Actively plant plot hooks and leave mysteries.
 5.  **Very important**: Start your response directly with the chapter title line. **Do NOT** write anything before this line (no greetings, confirmations, comments, etc.).
 6.  Do not use any Markdown formatting (no bold, no italics). Do not use asterisks (*) or underscores (_) for emphasis.
 7.  **Dialogue Format**: **Always** use double quotation marks ("") to enclose dialogue. **Never** use em dashes (—) for dialogues.
 8.  **Writing Style**: The prose should resemble that of a published novel, not a script.
''';

const LanguagePrompts _englishPrompts = LanguagePrompts(
  systemChapter: 'You are a writer who writes novel chapters based on the specified conditions. Follow the instructions strictly.',
  systemHiragana: 'あなたは日本語の単語のひらがなの読みを提供するアシスタントです。',
  systemRoadmap: 'You are an assistant specializing in summarizing novel plots.',
  commonInstructions: '$_enRules\n\n$_showDontTellPrinciple',
  firstChapterIntro: 'Create the **first chapter** of a new novel in [NOVEL_LANGUAGE] with the following characteristics:',
  nextChapterIntro: 'Write the **next chapter (Chapter [NEXT_CHAPTER_NUMBER])** for the novel "[NOVEL_TITLE]".',
  finalChapterIntro: 'Write the **final chapter** for the novel "[NOVEL_TITLE]", bringing the story to a satisfying conclusion.',
  finalChapterSpecificInstructions: '''
 Additional instructions for the final chapter:
 - Create a consistent ending based on the progression of the story so far. Resolve or conclude major plot hooks and mysteries as much as possible.
 - Describe the final situation and feelings of the characters.
 ''',
  contextSectionHeader: "CONTEXT:",
  contextLastChapterHeader: "Last Chapter (Chapter [CHAPTER_NUMBER]):",
  contextSimilarSectionHeader: "Relevant Context:",
  contextLastSentenceHeader: "As a reminder, the last sentence was:",
  contextFollowInstruction: "\n**Absolute Priority:** The story must be a direct and logical continuation of the last sentence, while remaining consistent with the content of the last chapter and the relevant context provided.",
  outputFormatFirst: '''
 Required output format (do not write anything before this line):
 Chapter 1: [An engaging title for this first chapter]

 [Write the content of Chapter 1 here...]
 ''',
  outputFormatNext: '''
 Required output format (do not write anything before this line):
 Chapter [NEXT_CHAPTER_NUMBER]: [An interesting title for this new chapter]

 [Write the content of Chapter [NEXT_CHAPTER_NUMBER] here...]
 ''',
  outputFormatFinal: '''
 Required output format (do not write anything before this line):
 Final Chapter: [A moving or thought-provoking title for this final chapter]

 [Write the content of the final chapter here...]
 ''',
  roadmapUpdatePrompt: '''
Here is the current overall summary (the roadmap) of the novel "[NOVEL_TITLE]".
<Current Roadmap>
[CURRENT_ROADMAP]
</Current Roadmap>

And here is the content of the last 3 chapters of the story.
<Last 3 Chapters>
[LAST_3_CHAPTERS]
</Last 3 Chapters>

Your task is to **update** the current roadmap considering the events of the last 3 chapters.
**Important**: The summary must be written in a **natural and fluid narrative style**, as if you were telling the story to someone. Avoid bullet points or note-style writing. However, you **must include** the following information for the AI's context:
-   Full names of the characters (if available).
-   A clear timeline of major events.
-   Names of important locations where the action takes place.

The result must be a **single, new, complete, and coherent paragraph** that covers the story from its beginning to the present.
Your response must only contain the text of the updated summary. Do NOT start your response with a title.
''',
  roadmapCreatePrompt: '''
Here is the content of the **first three chapters** of the novel "[NOVEL_TITLE]".
<First Three Chapters>
[INITIAL_CHAPTERS]
</First Three Chapters>

Your task is to create the **first overall roadmap** of the story based on these chapters.
**Important**: The summary must be written in a **natural and fluid narrative style**, as if you were telling the story to someone. Avoid bullet points or note-style writing. However, you **must include** the following information for the AI's context:
-   Full names of the characters (if available).
-   A clear timeline of major events.
-   Names of important locations where the action takes place.

The result must be a **single coherent paragraph** that covers the events from the beginning to the present.
Your response must only contain the text of the summary. Do NOT start your response with a title.
''',
  titleFirst: 'Chapter 1',
  titleFinal: 'Final Chapter',
  titleChapterPrefix: 'Chapter ',
  titleChapterSuffix: '',
  contextNotAvailable: "No context available.",
  firstChapterContext: "This is the first chapter.",
);


// Français
const _frRules = '''
 Règles strictes :
 1.  Écrivez en français [NOVEL_LANGUAGE].
 2.  La longueur du chapitre doit être d'environ 3000 caractères.
 3.  Maintenez la cohérence avec le genre "[NOVEL_GENRE]" et les spécifications "[NOVEL_SPECIFICATIONS]".
 4.  Rendez l'histoire captivante et donnez envie au lecteur de continuer à lire (sauf pour le chapitre final). Plantez activement des rebondissements et laissez des mystères.
 5.  **Très important** : Commencez votre réponse directement par la ligne du titre du chapitre. **N'écrivez RIEN** avant cette ligne (pas de salutations, confirmations, commentaires, etc.).
 6.  N'utilisez aucun formatage Markdown (pas de gras, pas d'italique). N'utilisez pas d'astérisques (*) ou de tirets bas (_) pour l'emphase.
 7.  **Format des dialogues**: Utilisez **toujours** des guillemets français (« ») ou des guillemets doubles ("") pour encadrer les dialogues. **N'utilisez jamais** de tirets cadratins (—) pour les dialogues.
 8.  **Style d'écriture** : La prose doit ressembler à celle d'un roman publié, pas à un script.
''';

const _frShowDontTell = '''
Principe d'écriture fondamental - "Montrer, ne pas dire" :
9.  **Ne résumez PAS les événements**. Ne faites pas d'avance rapide dans l'histoire. Concentrez-vous sur une seule scène significative ou une courte période, plutôt que d'essayer de couvrir trop de terrain en un seul chapitre.
10. **Décrivez en détail** : Décrivez l'atmosphère des lieux, les expressions faciales des personnages et les détails sensoriels (odeurs, sons, textures).
11. **Dépeignez la vie intérieure** : Au lieu d'énoncer directement l'émotion d'un personnage (par ex., "Il était triste"), **montrez-la** à travers ses actions, ses pensées et ses dialogues (par ex., "Ses épaules s'affaissèrent et son regard resta fixé sur le sol.").
12. **Rythme** : **Ne** précipitez **pas** l'histoire. Prenez du temps pour la psychologie des personnages et la construction du monde. Posez des bases suffisantes avant les événements majeurs.
13. **Cohérence** : Assurez-vous que les actions des personnages sont cohérentes avec leur personnalité et leurs motivations établies. Maintenez le déroulement logique de l'intrigue en fonction du contexte fourni.
''';

const LanguagePrompts _frenchPrompts = LanguagePrompts(
  systemChapter: 'Vous êtes un écrivain qui rédige des chapitres de romans en fonction des conditions spécifiées. Suivez strictement les instructions.',
  systemHiragana: 'あなたは日本語の単語のひらがなの読みを提供するアシスタントです。',
  systemRoadmap: 'Vous êtes un assistant spécialisé dans le résumé d\'intrigues de romans.',
  commonInstructions: '$_frRules\n\n$_frShowDontTell',
  firstChapterIntro: 'Créez le **premier chapitre** d\'un nouveau roman en [NOVEL_LANGUAGE] avec les caractéristiques suivantes :',
  nextChapterIntro: 'Écrivez le **chapitre suivant (Chapitre [NEXT_CHAPTER_NUMBER])** pour le roman "[NOVEL_TITLE]".',
  finalChapterIntro: 'Écrivez le **chapitre final** pour le roman "[NOVEL_TITLE]", menant l\'histoire à une conclusion satisfaisante.',
  finalChapterSpecificInstructions: '''
 Instructions supplémentaires pour le chapitre final :
 - Créez une fin cohérente basée sur la progression de l'histoire jusqu'à présent. Résolvez ou concluez les principaux rebondissements et mystères autant que possible.
 - Décrivez la situation finale et les sentiments des personnages.
 ''',
  contextSectionHeader: "CONTEXTE:",
  contextLastChapterHeader: "Dernier chapitre (Chapitre [CHAPTER_NUMBER]):",
  contextSimilarSectionHeader: "Contexte pertinent :",
  contextLastSentenceHeader: "Pour rappel, la dernière phrase était :",
  contextFollowInstruction: "\n**Priorité absolue :** La suite doit être une continuation directe et logique de la dernière phrase, tout en restant cohérente avec le contenu du dernier chapitre et le contexte pertinent fourni.",
  outputFormatFirst: '''
 Format de sortie requis (n'écrivez rien avant cette ligne) :
 Chapitre 1 : [Un titre captivant pour ce premier chapitre]

 [Écrivez le contenu du Chapitre 1 ici...]
 ''',
  outputFormatNext: '''
 Format de sortie requis (n'écrivez rien avant cette ligne) :
 Chapitre [NEXT_CHAPTER_NUMBER] : [Un titre intéressant pour ce nouveau chapitre]

 [Écrivez le contenu du Chapitre [NEXT_CHAPTER_NUMBER] ici...]
 ''',
  outputFormatFinal: '''
 Format de sortie requis (n'écrivez rien avant cette ligne) :
 Chapitre Final : [Un titre émouvant ou stimulant pour ce chapitre final]

 [Écrivez le contenu du chapitre final ici...]
 ''',
  roadmapUpdatePrompt: '''
Voici le résumé global actuel (la fiche de route) du roman "[NOVEL_TITLE]".
<Fiche de route actuelle>
[CURRENT_ROADMAP]
</Fiche de route actuelle>

Et voici le contenu des 3 derniers chapitres de l'histoire.
<3 derniers chapitres>
[LAST_3_CHAPTERS]
</3 derniers chapitres>

Votre tâche est de **mettre à jour** la fiche de route actuelle en tenant compte des événements des 3 derniers chapitres.
**Important** : Le résumé doit être rédigé dans un **style narratif naturel et fluide**, comme si vous racontiez l'histoire à quelqu'un. Évitez les listes à puces ou le style "notes". Cependant, vous devez **impérativement inclure** les informations suivantes pour le contexte de l'IA :
-   Les noms et prénoms des personnages (si disponibles).
-   Une chronologie claire des événements majeurs.
-   Les noms des lieux importants où se déroule l'action.

Le résultat doit être un **unique paragraphe, nouveau, complet et cohérent**, qui couvre l'histoire depuis son début jusqu'à maintenant.
Votre réponse ne doit contenir que le texte du résumé mis à jour. Ne commencez PAS votre réponse par un titre.
''',
  roadmapCreatePrompt: '''
Voici le contenu des **trois premiers chapitres** du roman "[NOVEL_TITLE]".
<Trois premiers chapitres>
[INITIAL_CHAPTERS]
</Trois premiers chapitres>

Votre tâche est de créer la **première fiche de route globale** de l'histoire en vous basant sur ces chapitres.
**Important** : Le résumé doit être rédigé dans un **style narratif naturel et fluide**, comme si vous racontiez l'histoire à quelqu'un. Évitez les listes à puces ou le style "notes". Cependant, vous devez **impérativement inclure** les informations suivantes pour le contexte de l'IA :
-   Les noms et prénoms des personnages (si disponibles).
-   Une chronologie claire des événements majeurs.
-   Les noms des lieux importants où se déroule l'action.

Le résultat doit être un **unique paragraphe cohérent** qui couvre les événements du début jusqu'à maintenant.
Votre réponse ne doit contenir que le texte du résumé. Ne commencez PAS votre réponse par un titre.
''',
  titleFirst: 'Chapitre 1',
  titleFinal: 'Chapitre Final',
  titleChapterPrefix: 'Chapitre ',
  titleChapterSuffix: '',
  contextNotAvailable: "Pas de contexte disponible.",
  firstChapterContext: "C'est le premier chapitre.",
);

// Espagnol (Spanish)
const LanguagePrompts _spanishPrompts = LanguagePrompts(
  systemChapter: 'Eres un escritor que redacta capítulos de novelas según las condiciones especificadas. Sigue las instrucciones estrictamente.',
  systemHiragana: 'あなたは日本語の単語のひらがなの読みを提供するアシスタントです。',
  systemRoadmap: 'Eres un asistente especializado en resumir tramas de novelas.',
  commonInstructions: '''
 Reglas estrictas:
 1.  Escribe en [NOVEL_LANGUAGE].
 2.  La longitud del capítulo debe ser de aproximadamente 3000 caracteres.
 3.  Mantén la coherencia con el género "[NOVEL_GENRE]" y las especificaciones "[NOVEL_SPECIFICATIONS]".
 4.  Haz la historia atractiva y que el lector quiera seguir leyendo (excepto en el capítulo final).
 5.  **Muy importante**: Comienza tu respuesta directamente con la línea del título del capítulo. **NO** escribas nada antes de esta línea.
 6.  No uses ningún formato Markdown (negrita, cursiva).
 7.  **Formato de diálogo**: Usa **siempre** comillas dobles ("") para los diálogos.
 8.  **Estilo de escritura**: La prosa debe parecerse a la de una novela publicada, no a un guion.

Principio de escritura - "Mostrar, no contar":
9.  **NO resumas los eventos**. Concéntrate en una sola escena significativa.
10. **Describe en detalle**: La atmósfera, las expresiones faciales, los detalles sensoriales.
11. **Representa la vida interior**: Muestra las emociones a través de acciones, no las nombres directamente.
12. **Ritmo**: No apresures la historia. Tómate tiempo para la psicología de los personajes.
13. **Coherencia**: Asegúrate de que las acciones de los personajes sean coherentes.
''',
  firstChapterIntro: 'Crea el **primer capítulo** de una nueva novela en [NOVEL_LANGUAGE] con las siguientes características:',
  nextChapterIntro: 'Escribe el **siguiente capítulo (Capítulo [NEXT_CHAPTER_NUMBER])** para la novela "[NOVEL_TITLE]".',
  finalChapterIntro: 'Escribe el **capítulo final** para la novela "[NOVEL_TITLE]", llevando la historia a una conclusión satisfactoria.',
  finalChapterSpecificInstructions: 'Instrucciones adicionales para el capítulo final: Crea un final coherente. Resuelve las tramas principales. Describe la situación final de los personajes.',
  contextSectionHeader: "CONTEXTO:",
  contextLastChapterHeader: "Último capítulo (Capítulo [CHAPTER_NUMBER]):",
  contextSimilarSectionHeader: "Contexto relevante:",
  contextLastSentenceHeader: "Como recordatorio, la última frase fue:",
  contextFollowInstruction: "\n**Prioridad absoluta:** La historia debe ser una continuación directa y lógica de la última frase.",
  outputFormatFirst: 'Formato requerido:\nCapítulo 1: [Título atractivo]\n\n[Contenido del Capítulo 1 aquí...]',
  outputFormatNext: 'Formato requerido:\nCapítulo [NEXT_CHAPTER_NUMBER]: [Título interesante]\n\n[Contenido del Capítulo [NEXT_CHAPTER_NUMBER] aquí...]',
  outputFormatFinal: 'Formato requerido:\nCapítulo Final: [Título emotivo]\n\n[Contenido del capítulo final aquí...]',
  roadmapUpdatePrompt: 'Actualiza el resumen de la novela "[NOVEL_TITLE]" con los eventos de los últimos 3 capítulos. El resultado debe ser un único párrafo narrativo.',
  roadmapCreatePrompt: 'Crea el primer resumen de la novela "[NOVEL_TITLE]" basándote en los tres primeros capítulos. El resultado debe ser un único párrafo narrativo.',
  titleFirst: 'Capítulo 1',
  titleFinal: 'Capítulo Final',
  titleChapterPrefix: 'Capítulo ',
  titleChapterSuffix: '',
  contextNotAvailable: "No hay contexto disponible.",
  firstChapterContext: "Este es el primer capítulo.",
);

// Italien (Italian)
const LanguagePrompts _italianPrompts = LanguagePrompts(
  systemChapter: 'Sei uno scrittore che scrive capitoli di romanzi in base alle condizioni specificate. Segui rigorosamente le istruzioni.',
  systemHiragana: 'あなたは日本語の単語のひらがなの読みを提供するアシスタントです。',
  systemRoadmap: 'Sei un assistente specializzato nel riassumere trame di romanzi.',
  commonInstructions: '''
 Regole severe:
 1.  Scrivi in [NOVEL_LANGUAGE].
 2.  La lunghezza del capitolo dovrebbe essere di circa 3000 caratteri.
 3.  Mantieni la coerenza con il genere "[NOVEL_GENRE]" e le specifiche "[NOVEL_SPECIFICATIONS]".
 4.  Rendi la storia coinvolgente e invoglia il lettore a continuare a leggere (tranne per il capitolo finale).
 5.  **Molto importante**: Inizia la tua risposta direttamente con la riga del titolo del capitolo. **NON** scrivere nulla prima di questa riga.
 6.  Non usare alcun formato Markdown (grassetto, corsivo).
 7.  **Formato dei dialoghi**: Usa **sempre** le virgolette doppie ("") per i dialoghi.
 8.  **Stile di scrittura**: La prosa deve assomigliare a quella di un romanzo pubblicato, non a una sceneggiatura.

Principio di scrittura - "Mostra, non raccontare":
9.  **NON riassumere gli eventi**. Concentrati su una singola scena significativa.
10. **Descrivi in dettaglio**: L'atmosfera, le espressioni facciali, i dettagli sensoriali.
11. **Rappresenta la vita interiore**: Mostra le emozioni attraverso le azioni, non nominarle direttamente.
12. **Ritmo**: Non affrettare la storia. Prenditi tempo per la psicologia dei personaggi.
13. **Coerenza**: Assicurati che le azioni dei personaggi siano coerenti.
''',
  firstChapterIntro: 'Crea il **primo capitolo** di un nuovo romanzo in [NOVEL_LANGUAGE] con le seguenti caratteristiche:',
  nextChapterIntro: 'Scrivi il **capitolo successivo (Capitolo [NEXT_CHAPTER_NUMBER])** per il romanzo "[NOVEL_TITLE]".',
  finalChapterIntro: 'Scrivi il **capitolo finale** per il romanzo "[NOVEL_TITLE]", portando la storia a una conclusione soddisfacente.',
  finalChapterSpecificInstructions: 'Istruzioni aggiuntive per il capitolo finale: Crea un finale coerente. Risolvi le trame principali. Descrivi la situazione finale dei personaggi.',
  contextSectionHeader: "CONTESTO:",
  contextLastChapterHeader: "Ultimo capitolo (Capitolo [CHAPTER_NUMBER]):",
  contextSimilarSectionHeader: "Contesto rilevante:",
  contextLastSentenceHeader: "Per promemoria, l'ultima frase era:",
  contextFollowInstruction: "\n**Priorità assoluta:** La storia deve essere una continuazione diretta e logica dell'ultima frase.",
  outputFormatFirst: 'Formato richiesto:\nCapitolo 1: [Titolo accattivante]\n\n[Contenuto del Capitolo 1 qui...]',
  outputFormatNext: 'Formato richiesto:\nCapitolo [NEXT_CHAPTER_NUMBER]: [Titolo interessante]\n\n[Contenuto del Capitolo [NEXT_CHAPTER_NUMBER] qui...]',
  outputFormatFinal: 'Formato richiesto:\nCapitolo Finale: [Titolo commovente]\n\n[Contenuto del capitolo finale qui...]',
  roadmapUpdatePrompt: 'Aggiorna il riassunto del romanzo "[NOVEL_TITLE]" con gli eventi degli ultimi 3 capitoli. Il risultato deve essere un unico paragrafo narrativo.',
  roadmapCreatePrompt: 'Crea il primo riassunto del romanzo "[NOVEL_TITLE]" basandoti sui primi tre capitoli. Il risultato deve essere un unico paragrafo narrativo.',
  titleFirst: 'Capitolo 1',
  titleFinal: 'Capitolo Finale',
  titleChapterPrefix: 'Capitolo ',
  titleChapterSuffix: '',
  contextNotAvailable: "Nessun contesto disponibile.",
  firstChapterContext: "Questo è il primo capitolo.",
);

// Coréen (Korean)
const LanguagePrompts _koreanPrompts = LanguagePrompts(
  systemChapter: '당신은 지정된 조건에 따라 소설의 장을 쓰는 작가입니다. 지시사항을 엄격히 따르십시오.',
  systemHiragana: 'あなたは日本語の単語のひらがなの読みを提供するアシスタントです。',
  systemRoadmap: '당신은 소설 줄거리 요약을 전문으로 하는 어시스턴트입니다.',
  commonInstructions: '''
 엄격한 규칙:
 1.  [NOVEL_LANGUAGE]로 작성하십시오.
 2.  챕터 길이는 약 2000자여야 합니다.
 3.  장르 "[NOVEL_GENRE]" 및 사양 "[NOVEL_SPECIFICATIONS]"과의 일관성을 유지하십시오.
 4.  이야기를 흥미롭게 만들고 독자가 계속 읽고 싶게 만드십시오(마지막 챕터 제외).
 5.  **매우 중요**: 응답은 챕터 제목 줄로 바로 시작하십시오. 이 줄 앞에 아무것도 쓰지 마십시오.
 6.  마크다운 서식(굵게, 기울임꼴)을 사용하지 마십시오.
 7.  **대화 형식**: 대화에는 **항상** 큰따옴표("")를 사용하십시오.
 8.  **글쓰기 스타일**: 대본이 아닌 출판된 소설과 같은 산문이어야 합니다.

핵심 글쓰기 원칙 - "말하지 말고 보여주기":
9.  **사건을 요약하지 마십시오**. 한 장면에 집중하십시오.
10. **자세히 묘사하십시오**: 분위기, 표정, 감각적 세부 사항.
11. **내면의 삶을 묘사하십시오**: 행동을 통해 감정을 보여주십시오.
12. **속도**: 이야기를 서두르지 마십시오.
13. **일관성**: 등장인물의 행동이 일관성이 있는지 확인하십시오.
''',
  firstChapterIntro: '다음 특성을 가진 [NOVEL_LANGUAGE]의 새 소설의 **첫 번째 장**을 만드십시오:',
  nextChapterIntro: '소설 "[NOVEL_TITLE]"의 **다음 장(챕터 [NEXT_CHAPTER_NUMBER])**을 작성하십시오.',
  finalChapterIntro: '소설 "[NOVEL_TITLE]"의 **마지막 장**을 작성하여 만족스러운 결론으로 이야기를 마무리하십시오.',
  finalChapterSpecificInstructions: '마지막 장에 대한 추가 지침: 일관된 결말을 만드십시오. 주요 줄거리를 해결하십시오. 등장인물의 최종 상황을 묘사하십시오.',
  contextSectionHeader: "문맥:",
  contextLastChapterHeader: "마지막 장 (챕터 [CHAPTER_NUMBER]):",
  contextSimilarSectionHeader: "관련 문맥:",
  contextLastSentenceHeader: "참고로 마지막 문장은 다음과 같았습니다:",
  contextFollowInstruction: "\n**절대적 우선순위:** 이야기는 마지막 문장의 직접적이고 논리적인 연속이어야 합니다.",
  outputFormatFirst: '필수 형식:\n제 1 장: [매력적인 제목]\n\n[제 1 장 내용...]',
  outputFormatNext: '필수 형식:\n제 [NEXT_CHAPTER_NUMBER] 장: [흥미로운 제목]\n\n[제 [NEXT_CHAPTER_NUMBER] 장 내용...]',
  outputFormatFinal: '필수 형식:\n마지막 장: [감동적인 제목]\n\n[마지막 장 내용...]',
  roadmapUpdatePrompt: '지난 3개 챕터의 사건을 고려하여 소설 "[NOVEL_TITLE]"의 줄거리를 업데이트하십시오. 결과는 하나의 서술 단락이어야 합니다.',
  roadmapCreatePrompt: '처음 3개 챕터를 기반으로 소설 "[NOVEL_TITLE]"의 첫 번째 줄거리를 만드십시오. 결과는 하나의 서술 단락이어야 합니다.',
  titleFirst: '제 1 장',
  titleFinal: '마지막 장',
  titleChapterPrefix: '제 ',
  titleChapterSuffix: ' 장',
  contextNotAvailable: "사용 가능한 문맥 없음.",
  firstChapterContext: "이것은 첫 번째 장입니다.",
);

// Japonais
const _jpRules = '''
 厳守事項：
 1.  3000文字から4000文字程度の日本語で執筆してください。
 2.  指定された日本語レベル「[NOVEL_LEVEL]」を**厳守**してください。
 3.  ふりがなは**絶対に使用しないでください**。
 4.  章の終わりは**必ず**完全な文で終えてください。中途半端にしないでください。
 5.  ジャンル「[NOVEL_GENRE]」および特定の設定「[NOVEL_SPECIFICATIONS]」との一貫性を保ってください。
 6.  物語を面白くし、続きを読みたくなるようにしてください（最終章の場合を除く）。伏線を**積極的に**張り、謎を残してください。
 7.  **非常に重要**：回答は、指定された章のタイトル行から**直接**始めてください。この行の前には**絶対に何も**書かないでください（挨拶、確認、コメント等一切不要）。
 8.  マークダウン書式（太字、斜体など）は一切使用しないでください。強調のためにアスタリスク（*）やアンダースコア（_）を使用しないでください。
 9.  **会話のフォーマット**: 会話には**必ず**引用符（「」）を使用してください。ダッシュ（—）は絶対に使用しないでください。
 10. **文体**: 脚本ではなく、出版された小説のような散文を目指してください。
''';

const _jpShowDontTell = '''
執筆の最重要原則 - 「語るな、見せろ」：
11. **出来事を要約しない**：物語を早送りしないでください。一つの章で多くの出来事を詰め込むのではなく、一つの重要なシーンや短い時間軸に焦点を当ててください。
12. **詳細な描写**：場所の雰囲気、キャラクターの表情、五感（匂い、音、触感）を詳細に描写してください。
13. **内面の描写**：キャラクターの感情を直接的に「彼は悲しかった」と書くのではなく、その行動、思考、対話を通して感情を**示して**ください。（例：「彼の肩は落ち、視線は床に固定されたままだった。」）
14. **自然なペース配分**：物語を**急がせる必要はありません**。キャラクターの心理描写や世界の描写にも時間をかけてください。重要な出来事の前に十分な布石を打ってください。
15. **キャラクターとプロットの一貫性**：登場人物の性格、動機、過去の行動と矛盾しないように描写してください。提供されたコンテキストや以前の章との論理的な流れを維持してください。
16. **使用言語**: 回答は**絶対に日本語**で記述。他言語不可。
''';

const LanguagePrompts _japanesePrompts = LanguagePrompts(
  systemChapter: 'あなたは指定された条件に基づいて日本語の小説の章を書く作家です。指示に厳密に従ってください。',
  systemHiragana: 'あなたは日本語の単語のひらがなの読みを提供するアシスタントです。',
  systemRoadmap: 'あなたは小説のプロットを要約することに特化したアシスタントです。',
  commonInstructions: '$_jpRules\n\n$_jpShowDontTell',
  firstChapterIntro: '以下の特徴を持つ新しい日本語小説の**第一章**を作成してください：',
  nextChapterIntro: '小説「[NOVEL_TITLE]」の**次の章（第[NEXT_CHAPTER_NUMBER]章）**を執筆してください。',
  finalChapterIntro: '小説「[NOVEL_TITLE]」の**最終章**を執筆し、物語を満足のいく形で完結させてください。',
  finalChapterSpecificInstructions: '''
 最終章に関する追加指示：
 - これまでの物語の進行に基づき、一貫性のある結末を作り上げてください。主要な伏線や謎は可能な限り回収または解決してください。
 - 必ずしもハッピーエンドにする必要はありませんが、読後感の良い、記憶に残るような結末を提供してください。
 - キャラクターたちの最終的な状況や心情を描写してください。
 ''',
  contextSectionHeader: "コンテキスト:",
  contextLastChapterHeader: "前の章 (第[CHAPTER_NUMBER]章):",
  contextSimilarSectionHeader: "関連コンテキスト:",
  contextLastSentenceHeader: "念のため、最後の文は次のとおりでした:",
  contextFollowInstruction: "\n**最優先事項:** 物語は、提供された最後の文の直接的かつ論理的な続きである必要があり、同時に前の章の内容および関連コンテキストと一貫性を保つ必要があります。",
  outputFormatFirst: '''
 必須出力フォーマット（この行より前に何も書かないでください）：
 第一章 : [この最初の章に適した魅力的なタイトル]

 [第一章の内容をここに記述...]
 ''',
  outputFormatNext: '''
 必須出力フォーマット（この行より前に何も書かないでください）：
 第[NEXT_CHAPTER_NUMBER]章 : [この新しい章に適した興味を引くタイトル]

 [第[NEXT_CHAPTER_NUMBER]章の内容をここに記述...]
 ''',
  outputFormatFinal: '''
 必須出力フォーマット（この行より前に何も書かないでください）：
 最終章 : [この最終章に適した感動的な、あるいは示唆に富むタイトル]

 [最終章の内容をここに記述...]
 ''',
  roadmapUpdatePrompt: '''
以下は、小説「[NOVEL_TITLE]」の現在の全体的なあらすじ（ロードマップ）です。
<現在のロードマップ>
[CURRENT_ROADMAP]
</現在のロードマップ>

そして、これが物語の最新の3つの章の内容です。
<最新の3つの章>
[LAST_3_CHAPTERS]
</最新の3つの章>

あなたの仕事は、最新の3つの章の出来事を考慮して、現在のロードマップを**更新**することです。
**重要**：要約は、誰かに物語を語るような、**自然で流暢な文体**で書かれなければなりません。箇条書きやメモ形式は避けてください。ただし、IAが文脈を理解するために、以下の情報を**必ず**含めてください：
-   登場人物のフルネーム（可能な場合）
-   重要な出来事の時系列
-   物語の中で登場する場所の名前

最終的に、物語の最初から現在までを網羅した、**新しく、一貫性のある単一の段落**を作成してください。
出力は、更新されたあらすじのテキストのみでなければなりません。回答の冒頭にタイトルを付けないでください。
''',
  roadmapCreatePrompt: '''
以下は、小説「[NOVEL_TITLE]」の**最初の3つの章**の内容です。
<最初の3つの章>
[INITIAL_CHAPTERS]
</最初の3つの章>

あなたの仕事は、これらの章に基づいて、物語の開始から現在までの出来事を網羅した、**最初の全体的なあらすじ（ロードマップ）**を作成することです。
**重要**：要約は、誰かに物語を語るような、**自然で流暢な文体**で書かれなければなりません。箇条書きやメモ形式は避けてください。ただし、IAが文脈を理解するために、以下の情報を**必ず**含めてください：
-   登場人物のフルネーム（可能な場合）
-   重要な出来事の時系列
-   物語の中で登場する場所の名前

最終的に、物語の最初から現在までを網羅した、**一貫性のある単一の段落**を作成してください。
出力は、あらすじのテキストのみでなければなりません。回答の冒頭にタイトルを付けないでください。
''',
  titleFirst: '第一章',
  titleFinal: '最終章',
  titleChapterPrefix: '第',
  titleChapterSuffix: '章',
  contextNotAvailable: "特に指定なし",
  firstChapterContext: "これは最初の章です。",
);
