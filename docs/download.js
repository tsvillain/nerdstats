// Point the Download button at the latest release's DMG. Without JavaScript, or if the
// GitHub API fails or there is no release yet, the button keeps its link to the latest
// release page.
(function () {
  var button = document.getElementById("download");
  var note = document.getElementById("download-note");
  if (!button || !window.fetch) return;

  fetch("https://api.github.com/repos/tsvillain/nerdstats/releases/latest", {
    headers: { Accept: "application/vnd.github+json" }
  })
    .then(function (response) {
      if (!response.ok) throw new Error("HTTP " + response.status);
      return response.json();
    })
    .then(function (release) {
      var version = release.tag_name || "";
      var dmg = (release.assets || []).filter(function (asset) {
        return /\.dmg$/i.test(asset.name);
      })[0];
      if (dmg) {
        button.href = dmg.browser_download_url;
        note.textContent = (version ? version + " · " : "") + "DMG, " +
          Math.max(1, Math.round(dmg.size / 1048576)) + " MB";
      } else if (release.html_url) {
        button.href = release.html_url;
      }
      if (version) button.textContent = "Download " + version + " for macOS";
    })
    .catch(function () {
      // Keep the fallback link to the latest release page.
    });
})();
