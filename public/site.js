(function () {
  var config = window.SITE_CONFIG || {};
  var domain = (config.domain || window.location.host || "pypi.cyoahs.dev").replace(/^https?:\/\//, "");
  var packageName = config.packageName || "cyclonedds";
  var baseUrl = "https://" + domain.replace(/\/$/, "");

  var commands = {
    "extra-index": "pip install --extra-index-url " + baseUrl + "/simple " + packageName,
    index: "pip install --index-url " + baseUrl + "/simple " + packageName
  };

  Object.keys(commands).forEach(function (name) {
    document.querySelectorAll('[data-command="' + name + '"]').forEach(function (node) {
      node.textContent = commands[name];
    });
  });
})();
