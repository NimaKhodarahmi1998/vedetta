/* FieldVision concept: every piece of interface text, in Italian and English, and the language choice.
   The spoken lines, object names and checkpoints live in sim-core.js, with the scene that says them.
   It runs before the app loads, so the page appears in the right language from the start. */
(function (root) {
  'use strict';
  const TEXT = {
    it: {
      language: 'Lingua',
      subtitle: 'Guida per pedoni non vedenti, con la sola fotocamera di iPhone.',
      statusOk: 'Guida affidabile', statusBad: 'Guida non affidabile: troppo buio',
      streetView: 'La strada vera', mapView: 'La mappa 3D che iPhone costruisce dal vivo',
      tagReal: 'Realtà', tagMap: 'Mappa 3D dal vivo',
      legendSure: 'Confermato', legendMaybe: 'Forse', legendHidden: 'Nascosto', legendDanger: 'Pericolo', legendWarn: 'Non affidabile',
      startTitle: 'Ascolta come FieldVision guida un pedone non vedente',
      startBody: 'A sinistra la strada vera, a destra la mappa 3D che iPhone costruisce mentre la persona cammina. Per sentire voce e suoni, usa le cuffie.',
      startAudio: 'Avvia con audio', startSilent: 'Avvia senza audio',
      play: 'Riproduci', pause: 'Pausa', scrub: 'Posizione nella scena', captions: 'Sottotitoli',
      audioOff: 'Attiva audio', audioOn: 'Disattiva audio',
      // Sound cues, shown in brackets above the spoken line like SDH subtitles. The tick has none: it plays every 2 s.
      cue: { knock: 'Un colpo', flutter: 'Fremito', fast: 'Due impulsi forti', long: 'Lungo-lungo', rising: 'Due colpi in salita', prox: 'Bip sempre più rapidi' },
      // The words on the map's object labels. g is the object's Italian gender ending, s is seconds already formatted.
      tag: {
        far: 'Oggetto', maybe: 'forse', fast: 'veloce', memory: 'dalla memoria', ahead: 'davanti',
        sure: (g) => g === 'o' ? 'confermato' : 'confermata',
        hidden: (g, s) => (g === 'o' ? 'nascosto' : 'nascosta') + ' da ' + s + ' s',
      },
      decimal: ',', speech: 'it-IT',
    },
    en: {
      language: 'Language',
      subtitle: 'Guidance for blind pedestrians, using only the camera on iPhone.',
      statusOk: 'Guide reliable', statusBad: 'Guide unreliable: too dark',
      streetView: 'The real street', mapView: 'The 3D map iPhone builds live',
      tagReal: 'Real world', tagMap: 'Live 3D map',
      legendSure: 'Confirmed', legendMaybe: 'Maybe', legendHidden: 'Hidden', legendDanger: 'Danger', legendWarn: 'Unreliable',
      startTitle: 'Hear how FieldVision guides a blind pedestrian',
      startBody: 'On the left, the real street. On the right, the 3D map iPhone builds as the person walks. To hear the voice and sounds, use headphones.',
      startAudio: 'Start with Sound', startSilent: 'Start Without Sound',
      play: 'Play', pause: 'Pause', scrub: 'Scene position', captions: 'Subtitles',
      audioOff: 'Turn On Sound', audioOn: 'Turn Off Sound',
      cue: { knock: 'One knock', flutter: 'Flutter', fast: 'Two strong pulses', long: 'Long-long', rising: 'Two rising knocks', prox: 'Faster and faster beeps' },
      tag: {
        far: 'Object', maybe: 'maybe', fast: 'fast', memory: 'from memory', ahead: 'ahead',
        sure: () => 'confirmed',
        hidden: (g, s) => 'hidden for ' + s + ' s',
      },
      decimal: '.', speech: 'en-US',
    },
  };

  // The language picked last time, otherwise the browser's: Italian for an Italian browser, English for any other.
  function initial() {
    let saved = null;
    try { saved = localStorage.getItem('fieldvision-lang'); } catch (e) { /* storage can be blocked */ }
    return TEXT[saved] ? saved : /^it\b/i.test(navigator.language || '') ? 'it' : 'en';
  }
  function save(lang) { try { localStorage.setItem('fieldvision-lang', lang); } catch (e) { /* the choice lasts this visit */ } }

  // Sets the page's fixed text: data-i18n elements get their text, data-i18n-label ones their accessibility label.
  function apply(lang) {
    const T = TEXT[lang];
    document.documentElement.lang = lang;
    for (const el of document.querySelectorAll('[data-i18n]')) el.textContent = T[el.dataset.i18n];
    for (const el of document.querySelectorAll('[data-i18n-label]')) el.setAttribute('aria-label', T[el.dataset.i18nLabel]);
    for (const el of document.querySelectorAll('[data-lang]')) el.setAttribute('aria-pressed', String(el.dataset.lang === lang));
  }

  const lang = initial();
  apply(lang);
  root.FVText = { TEXT, lang, apply, save };
})(window);
