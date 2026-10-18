// Couleurs proposées aux établissements : les teintes système d'Apple, foncées juste assez
// pour qu'un texte blanc posé dessus reste lisible (contraste 4,5 au moins, vérifié par les tests).
// tint : boutons pleins et texte sur fond clair ; tintDark : texte et icônes en mode sombre.
export const THEMES = [
  { id: 'bleu', name: 'Bleu', tint: '#0071e3', tintDark: '#2997ff' },
  { id: 'indigo', name: 'Indigo', tint: '#5856d6', tintDark: '#817feb' },
  { id: 'violet', name: 'Violet', tint: '#a741db', tintDark: '#bf5af2' },
  { id: 'rose', name: 'Rose', tint: '#e0002b', tintDark: '#ff375f' },
  { id: 'rouge', name: 'Rouge', tint: '#e00b00', tintDark: '#ff453a' },
  { id: 'orange', name: 'Orange', tint: '#a86200', tintDark: '#ff9f0a' },
  { id: 'vert', name: 'Vert', tint: '#23863c', tintDark: '#30d158' },
  { id: 'turquoise', name: 'Turquoise', tint: '#227d8d', tintDark: '#40c8e0' },
  { id: 'marron', name: 'Marron', tint: '#886f4f', tintDark: '#ac8e68' },
  { id: 'graphite', name: 'Graphite', tint: '#6e6e73', tintDark: '#98989d' }
];

export const DEFAULT_THEME = 'bleu';

export function getTheme(id) {
  return THEMES.find((t) => t.id === id) || THEMES.find((t) => t.id === DEFAULT_THEME);
}
