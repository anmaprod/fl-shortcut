// Palettes proposées aux établissements. Partagé par le serveur (validation) et les pages.
// primary : en-têtes et boutons ; onPrimary : texte posé dessus ; soft : fonds teintés ; ink : texte sur soft.
export const THEMES = [
  { id: 'ocean', name: 'Océan', primary: '#0b5fa5', onPrimary: '#ffffff', soft: '#e7f0fa', ink: '#0b2747' },
  { id: 'bistrot', name: 'Bistrot', primary: '#8a1c2b', onPrimary: '#ffffff', soft: '#f8e9eb', ink: '#3d0c13' },
  { id: 'foret', name: 'Forêt', primary: '#1f6f43', onPrimary: '#ffffff', soft: '#e6f3eb', ink: '#0d3320' },
  { id: 'soleil', name: 'Soleil', primary: '#b93d0a', onPrimary: '#ffffff', soft: '#fdeee4', ink: '#4a1903' },
  { id: 'ardoise', name: 'Ardoise', primary: '#2f3b4c', onPrimary: '#ffffff', soft: '#eceff3', ink: '#151b24' },
  { id: 'framboise', name: 'Framboise', primary: '#b8185a', onPrimary: '#ffffff', soft: '#fbe8f0', ink: '#4b0a25' },
  { id: 'lavande', name: 'Lavande', primary: '#6a2bd0', onPrimary: '#ffffff', soft: '#f0e9fc', ink: '#2a0f56' },
  { id: 'lagon', name: 'Lagon', primary: '#0e7470', onPrimary: '#ffffff', soft: '#e3f4f3', ink: '#06312f' },
  { id: 'cafe', name: 'Café', primary: '#6f4327', onPrimary: '#ffffff', soft: '#f5ece6', ink: '#2e1a0e' },
  { id: 'nuit', name: 'Nuit', primary: '#111111', onPrimary: '#f5c518', soft: '#f3f3f1', ink: '#111111' }
];

export const DEFAULT_THEME = 'ocean';

export function getTheme(id) {
  return THEMES.find((t) => t.id === id) || THEMES.find((t) => t.id === DEFAULT_THEME);
}
