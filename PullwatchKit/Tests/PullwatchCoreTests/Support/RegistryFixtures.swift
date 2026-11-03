import Foundation

/// Ingekorte echte antwoorden van de registers (november 2026): dezelfde vorm en velden, minder
/// versies en dependencies.
enum RegistryFixtures {
    /// `GET registry.npmjs.org/express` met `Accept: application/vnd.npm.install-v1+json`.
    static let npmExpress = #"""
    {"name":"express","dist-tags":{"latest":"5.3.0"},"modified":"2026-10-09T12:56:55.078Z","versions":{
    "4.21.2":{"name":"express","version":"4.21.2","dependencies":{"qs":"6.13.0","body-parser":"1.20.3"},"engines":{"node":">= 0.10.0"}},
    "5.0.0":{"name":"express","version":"5.0.0","dependencies":{"qs":"6.13.0","body-parser":"^2.0.1"},"engines":{"node":">= 18"}},
    "5.3.0":{"name":"express","version":"5.3.0","dependencies":{"qs":"^6.16.0","body-parser":"^2.3.0"},"engines":{"node":">= 18"}},
    "0.14.1":{"name":"express","version":"0.14.1","deprecated":"express 0.x series is deprecated"}}}
    """#

    /// `GET registry.npmjs.org/react-dom`, verkort packument.
    static let npmReactDOM = #"""
    {"name":"react-dom","dist-tags":{"latest":"19.2.0"},"versions":{
    "18.3.1":{"name":"react-dom","version":"18.3.1","dependencies":{"scheduler":"^0.23.2","loose-envify":"^1.1.0"},"peerDependencies":{"react":"^18.3.1"}},
    "19.0.0":{"name":"react-dom","version":"19.0.0","dependencies":{"scheduler":"^0.25.0"},"peerDependencies":{"react":"^19.0.0"}},
    "19.2.0":{"name":"react-dom","version":"19.2.0","dependencies":{"scheduler":"^0.27.0"},"peerDependencies":{"react":"^19.2.0"}}}}
    """#

    /// `GET registry.npmjs.org/react`, verkort packument.
    static let npmReact = #"""
    {"name":"react","dist-tags":{"latest":"19.2.0"},"versions":{
    "18.3.1":{"name":"react","version":"18.3.1","dependencies":{"loose-envify":"^1.1.0"},"engines":{"node":">=0.10.0"}},
    "19.0.0":{"name":"react","version":"19.0.0","engines":{"node":">=0.10.0"}},
    "19.2.0":{"name":"react","version":"19.2.0","engines":{"node":">=0.10.0"}}}}
    """#

    /// `GET repo.packagist.org/p2/monolog/monolog.json`: verkleind, elke versie erft van de vorige.
    static let packagistMonolog = #"""
    {"minified":"composer/2.0","packages":{"monolog/monolog":[
    {"version":"3.12.1","version_normalized":"3.12.1.0","require":{"php":">=8.1","psr/log":"^2.0 || ^3.0"},"require-dev":{"phpunit/phpunit":"^10.5.17 || ^11.0.7"}},
    {"version":"3.12.0","version_normalized":"3.12.0.0"},
    {"version":"3.11.0","version_normalized":"3.11.0.0","require-dev":"__unset"},
    {"version":"2.11.1","version_normalized":"2.11.1.0","require":{"php":">=7.2","psr/log":"^1.0.1 || ^2.0 || ^3.0"}},
    {"version":"2.10.0","version_normalized":"2.10.0.0"},
    {"version":"2.0.0-beta1","version_normalized":"2.0.0.0-beta1","require":{"php":"^7.1","psr/log":"^1.0.1"}}]}}
    """#

    /// `GET crates.io/api/v1/crates/anyhow`.
    static let cratesAnyhow = #"""
    {"crate":{"id":"anyhow","max_stable_version":"1.0.104","max_version":"1.0.104"},"versions":[
    {"num":"1.0.104","rust_version":"1.68","yanked":false},
    {"num":"1.0.103","rust_version":"1.68","yanked":true},
    {"num":"1.0.80","rust_version":"1.39","yanked":false},
    {"num":"1.0.30","rust_version":null,"yanked":false}]}
    """#

    /// `GET crates.io/api/v1/crates/anyhow/1.0.80/dependencies`.
    static let cratesAnyhowDependencies = #"""
    {"dependencies":[{"id":9421791,"version_id":1056146,"crate_id":"futures","req":"^0.3","optional":false,"kind":"dev"},
    {"id":9421793,"version_id":1056146,"crate_id":"syn","req":"^2.0","optional":false,"kind":"dev"},
    {"id":9421790,"version_id":1056146,"crate_id":"backtrace","req":"^0.3.51","optional":true,"kind":"normal"}]}
    """#

    /// `GET api.nuget.org/v3/registration5-gz-semver2/newtonsoft.json/index.json`: pagina's in de index.
    static let nugetNewtonsoft = #"""
    {"count":1,"items":[{"@id":"https://api.nuget.org/v3/registration5-gz-semver2/newtonsoft.json/index.json#page/12.0.1/14.0.1-beta2","lower":"12.0.1","upper":"14.0.1-beta2","count":3,"items":[
    {"catalogEntry":{"version":"13.0.1","listed":true,"dependencyGroups":[{"targetFramework":".NETFramework4.5"},{"targetFramework":".NETStandard2.0"}]}},
    {"catalogEntry":{"version":"13.0.4","listed":true,"dependencyGroups":[{"targetFramework":".NETFramework4.5"},{"targetFramework":"net6.0"},{"targetFramework":".NETStandard2.0"}]}},
    {"catalogEntry":{"version":"14.0.1-beta1","listed":true,"dependencyGroups":[{"targetFramework":"net10.0"},{"targetFramework":".NETStandard2.0"}]}}]}]}
    """#

    /// `GET api.nuget.org/v3/registration5-gz-semver2/serilog/index.json`: pagina's los.
    static let nugetSerilog = #"""
    {"count":2,"items":[
    {"@id":"https://api.nuget.org/v3/registration5-gz-semver2/serilog/page/3.0.2-dev-02042/4.3.0-dev-02358.json","lower":"3.0.2-dev-02042","upper":"4.3.0-dev-02358","count":64},
    {"@id":"https://api.nuget.org/v3/registration5-gz-semver2/serilog/page/4.3.0-dev-02360/4.4.1-dev-02453.json","lower":"4.3.0-dev-02360","upper":"4.4.1-dev-02453","count":26}]}
    """#

    /// De laatste pagina van Serilog.
    static let nugetSerilogPage = #"""
    {"@id":"https://api.nuget.org/v3/registration5-gz-semver2/serilog/page/4.3.0-dev-02360/4.4.1-dev-02453.json","lower":"4.3.0-dev-02360","upper":"4.4.1-dev-02453","count":2,"items":[
    {"catalogEntry":{"version":"4.3.0","listed":true,"dependencyGroups":[{"targetFramework":".NETFramework4.6.2","dependencies":[{"id":"System.Diagnostics.DiagnosticSource","range":"[8.0.1, )"},{"id":"System.Threading.Channels","range":"[8.0.0, )"}]},{"targetFramework":"net8.0","dependencies":[]},{"targetFramework":".NETStandard2.0","dependencies":[{"id":"System.Diagnostics.DiagnosticSource","range":"[8.0.1, )"}]}]}},
    {"catalogEntry":{"version":"4.4.1-dev-02453","listed":true,"dependencyGroups":[{"targetFramework":"net10.0","dependencies":[]},{"targetFramework":"net8.0","dependencies":[]}]}}]}
    """#

    /// Een package dat alleen voor moderne .NET gebouwd is (zoals Serilog voor net8.0/net9.0).
    static let nugetModernOnly = #"""
    {"count":1,"items":[{"@id":"https://api.nuget.org/v3/registration5-gz-semver2/acme.modern/index.json#page/1.0.0/2.0.0","lower":"1.0.0","upper":"2.0.0","count":2,"items":[
    {"catalogEntry":{"version":"1.0.0","listed":true,"dependencyGroups":[{"targetFramework":"net6.0","dependencies":[]},{"targetFramework":"net8.0","dependencies":[]}]}},
    {"catalogEntry":{"version":"2.0.0","listed":true,"dependencyGroups":[{"targetFramework":"net9.0","dependencies":[]},{"targetFramework":"net10.0","dependencies":[]}]}}]}]}
    """#

    /// `GET rubygems.org/api/v1/versions/rack.json`.
    static let rubyGemsRack = #"""
    [{"number":"3.2.8","platform":"ruby","prerelease":false,"ruby_version":">= 2.4.0","rubygems_version":">= 0"},
    {"number":"3.2.8","platform":"java","prerelease":false,"ruby_version":">= 3.0.0","rubygems_version":">= 0"},
    {"number":"3.2.0","platform":"ruby","prerelease":false,"ruby_version":">= 2.4.0","rubygems_version":">= 0"},
    {"number":"3.1.0.rc1","platform":"ruby","prerelease":true,"ruby_version":">= 2.4.0","rubygems_version":">= 0"},
    {"number":"3.0.0","platform":"ruby","prerelease":false,"ruby_version":">= 2.4.0","rubygems_version":">= 0"},
    {"number":"2.2.9","platform":"ruby","prerelease":false,"ruby_version":">= 2.3.0","rubygems_version":">= 0"}]
    """#

    /// `GET rubygems.org/api/v2/rubygems/rack/versions/3.0.0.json`.
    static let rubyGemsRack300 = #"""
    {"name":"rack","version":"3.0.0","ruby_version":">= 2.4.0","rubygems_version":">= 0","dependencies":{"development":[{"name":"minitest","requirements":"~> 5.0"},{"name":"rake","requirements":">= 0"}],"runtime":[]}}
    """#

    /// `GET pypi.org/pypi/requests/json`.
    static let pypiRequests = #"""
    {"info":{"name":"requests","version":"2.34.2","requires_python":">=3.10"},"releases":{
    "2.31.0":[{"packagetype":"bdist_wheel","requires_python":">=3.7","yanked":false},{"packagetype":"sdist","requires_python":">=3.7","yanked":false}],
    "2.32.0":[{"packagetype":"bdist_wheel","requires_python":">=3.8","yanked":true},{"packagetype":"sdist","requires_python":">=3.8","yanked":true}],
    "2.32.3":[{"packagetype":"bdist_wheel","requires_python":">=3.8","yanked":false},{"packagetype":"sdist","requires_python":">=3.8","yanked":false}],
    "2.34.2":[{"packagetype":"bdist_wheel","requires_python":">=3.10","yanked":false},{"packagetype":"sdist","requires_python":">=3.10","yanked":false}]}}
    """#

    /// `GET pypi.org/pypi/requests/2.31.0/json`.
    static let pypiRequests2310 = #"""
    {"info":{"name":"requests","version":"2.31.0","requires_python":">=3.7","requires_dist":["charset-normalizer (<4,>=2)","idna (<4,>=2.5)","urllib3 (<3,>=1.21.1)","certifi (>=2017.4.17)","PySocks (!=1.5.7,>=1.5.6) ; extra == 'socks'","chardet (<6,>=3.0.2) ; extra == 'use_chardet_on_py3'"]}}
    """#

    /// `GET proxy.golang.org/github.com/spf13/cobra/@latest` en `@v/v1.8.0.mod`.
    static let goCobraLatest = #"{"Version":"v1.10.2","Time":"2025-12-03T23:51:15Z","Origin":{"VCS":"git","URL":"https://github.com/spf13/cobra","Ref":"refs/tags/v1.10.2"}}"#
    static let goCobraMod = """
    module github.com/spf13/cobra

    go 1.15

    require (
    \tgithub.com/cpuguy83/go-md2man/v2 v2.0.3
    \tgithub.com/inconshreveable/mousetrap v1.1.0
    \tgithub.com/spf13/pflag v1.0.5
    \tgopkg.in/yaml.v3 v3.0.1
    )
    """
}
