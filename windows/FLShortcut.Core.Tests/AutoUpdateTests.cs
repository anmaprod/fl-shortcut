using System.Security.Cryptography;
using System.Text;
using FLShortcut.Core;
using Xunit;

namespace FLShortcut.Core.Tests;

/// Mises à jour toutes seules (19/11) : mêmes règles que le Mac (AutoUpdateTests.swift).
public sealed class AutoUpdateTests
{
    private static readonly byte[] Manifest = Encoding.UTF8.GetBytes(
        """{"version":"0.4.0","mac":null,"windows":{"url":"https://github.com/anmaprod/fl-shortcut/releases/download/v0.4.0/FLShortcuts-Windows-Setup.exe","sha256":"ab"}}""");

    private static (string Pem, byte[] Signature) Sign(byte[] data)
    {
        using var key = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var der = key.SignData(data, HashAlgorithmName.SHA256, DSASignatureFormat.Rfc3279DerSequence);
        return (key.ExportSubjectPublicKeyInfoPem(), Encoding.UTF8.GetBytes(Convert.ToBase64String(der)));
    }

    [Fact]
    public void TheAppKeyIsReadable()
    {
        using var key = ECDsa.Create();
        key.ImportFromPem(UpdateRules.PublicKeyPem);
        Assert.Equal(256, key.KeySize);
    }

    /// Signé comme la CI (openssl dgst -sha256 -sign, clé UPDATE_SIGNING_KEY) : la clé de l'appli le lit. Version
    /// 0.0.0, sans fichier : jamais une mise à jour.
    [Fact]
    public void ASignatureMadeLikeTheCIIsAccepted()
    {
        var data = Encoding.UTF8.GetBytes("""{"version":"0.0.0","mac":null,"windows":null}""");
        var signature = Encoding.UTF8.GetBytes("MEUCIEEHgoA//ukZM3+Osf1UEaxdYGZF41HKnRGiR/pjI7C+AiEAjYq22oU7o1M3LKMCyo2b/KwjYo7JnO6gzvB+Q3POeAA=");
        Assert.Equal("0.0.0", UpdateRules.Verified(data, signature)?.Version);
    }

    [Fact]
    public void OnlyASignatureOfTheKeyIsAccepted()
    {
        var (pem, signature) = Sign(Manifest);
        var read = UpdateRules.Verified(Manifest, signature, pem);
        Assert.Equal("0.4.0", read?.Version);
        Assert.Equal("ab", read?.Windows?.Sha256);
        Assert.Null(read?.Mac);
        var tampered = (byte[])Manifest.Clone();
        tampered[15] = (byte)'9';
        Assert.Null(UpdateRules.Verified(tampered, signature, pem));
        Assert.Null(UpdateRules.Verified(Manifest, signature, Sign(Manifest).Pem));
        Assert.Null(UpdateRules.Verified(Manifest, signature));
        Assert.Null(UpdateRules.Verified(Manifest, Encoding.UTF8.GetBytes("pas une signature"), pem));
    }

    [Fact]
    public void VersionsCompareNumberByNumber()
    {
        Assert.True(UpdateRules.IsNewer("0.4.0", "0.3.9"));
        Assert.True(UpdateRules.IsNewer("0.10.0", "0.9.0"));
        Assert.True(UpdateRules.IsNewer("1.0.0", "0.99.99"));
        Assert.False(UpdateRules.IsNewer("0.4.0", "0.4.0"));
        Assert.False(UpdateRules.IsNewer("0.3.0", "0.4.0"));
        Assert.False(UpdateRules.IsNewer("0.4", "0.3.0"));
        Assert.False(UpdateRules.IsNewer("0.4.0-beta", "0.3.0"));
        Assert.False(UpdateRules.IsNewer("0.4.0", "?"));
    }

    [Fact]
    public void FilesComeOnlyFromTheReleasesOfTheRepository()
    {
        Assert.NotNull(UpdateRules.DownloadUri("https://github.com/anmaprod/fl-shortcut/releases/download/v0.4.0/FLShortcuts-Windows-Setup.exe"));
        Assert.Null(UpdateRules.DownloadUri("http://github.com/anmaprod/fl-shortcut/releases/download/v0.4.0/a.exe"));
        Assert.Null(UpdateRules.DownloadUri("https://example.com/anmaprod/fl-shortcut/releases/download/v0.4.0/a.exe"));
        Assert.Null(UpdateRules.DownloadUri("https://github.com/autre/depot/releases/download/v0.4.0/a.exe"));
        Assert.Null(UpdateRules.DownloadUri("https://github.com/anmaprod/fl-shortcut/releases/download/../../x.exe"));
    }

    [Fact]
    public void ChecksumAndWhenToInstall()
    {
        Assert.Equal("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                     UpdateRules.Sha256Hex(new MemoryStream(Encoding.UTF8.GetBytes("abc"))));
        Assert.True(UpdateRules.CanInstall(flRunning: false, windowOpen: false));
        Assert.False(UpdateRules.CanInstall(flRunning: true, windowOpen: false));
        Assert.False(UpdateRules.CanInstall(flRunning: false, windowOpen: true));
    }

    /// La clé publique est la même que celle du Mac (AutoUpdate.swift).
    [Fact]
    public void SameUpdateKeyAsTheMac()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null && !Directory.Exists(Path.Combine(dir.FullName, "Sources"))) dir = dir.Parent;
        var swift = File.ReadAllText(Path.Combine(dir!.FullName, "Sources", "FLShortcut", "AutoUpdate.swift"));
        string Body(string pem) => string.Concat(pem.Split('\n').Select(l => l.Trim()).Where(l => l.Length > 0 && !l.StartsWith("-----")));
        var start = swift.IndexOf("-----BEGIN PUBLIC KEY-----", StringComparison.Ordinal);
        var end = swift.IndexOf("-----END PUBLIC KEY-----", start, StringComparison.Ordinal);
        Assert.True(start >= 0 && end > start);
        Assert.Equal(Body(UpdateRules.PublicKeyPem), Body(swift[start..end]));
    }
}
