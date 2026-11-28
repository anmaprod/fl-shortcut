# Windows MIDI Services — métadonnées de l'API

`Windows.Devices.Midi2.winmd` : métadonnées de l'API Windows MIDI Services (Windows.Devices.Midi2), tirées du paquet
NuGet `Windows.Devices.Midi2` 0.99.92-preview.11 (version « In-box Preview 11 », API figée), publié par Microsoft sur
https://github.com/microsoft/MIDI/releases (le paquet n'est pas sur nuget.org). Seules les métadonnées sont ici :
l'appli en tire une projection C# (CsWinRT) à la compilation sous Windows ; l'implémentation est celle de Windows
(Windows 11 25H2 et plus récent, avec la mise à jour de novembre 2026). Sans elle, l'appli garde loopMIDI.

Depuis le 21/11, l'appli porte aussi la copie de l'API elle-même (`Windows.Devices.Midi2.dll` et `.pri`, dossiers
`runtimes/win-x64` et `runtimes/win-arm64/native` du même paquet, signés par Microsoft) : l'API n'est pas encore dans
Windows, seuls le service MIDI et ses ports « boucle » y sont (Windows 11 25H2 et plus récent). Ces fichiers ne sont
pas dans le dépôt : la CI télécharge le paquet
(https://github.com/microsoft/MIDI/releases/download/inbox-preview-11/Windows.Devices.Midi2.0.99.92-preview.11.nupkg,
SHA-256 13afc6e6da2adac309ab8c174352f46f1c0ebe2d79e65475bd6274defb73df74) et les range dans `win-x64/` et
`win-arm64/` ici.

Accord de Microsoft pour livrer cette préversion (« Developer Go-live agreement », release inbox-preview-11) : la
retirer quand l'API sera dans Windows et suivre les préversions ; dire aux gens que l'appli utilise une API en
préversion ; jamais sur Windows plus ancien que 11 25H2 (l'installeur ne la pose que là, l'appli ne s'en sert que là :
`MidiServicesSupport`) ; signaler les bugs sur GitHub ; prévenir les gens quand une version faite pour l'API de
Windows sort.

Licence : MIT.

Copyright (c) Microsoft Corporation.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit
persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the
Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
