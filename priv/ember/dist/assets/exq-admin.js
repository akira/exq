eval("//# sourceURL=vendor/ember-cli/loader.js");

;eval("define(\"exq-admin/adapters/application\", \n  [\"exports\"],\n  function(__exports__) {\n    \"use strict\";\n    var ApplicationAdapter;\n\n    ApplicationAdapter = DS.ActiveModelAdapter.extend({\n      namespace: \"\" + window.exqNamespace + \"api\"\n    });\n\n    __exports__[\"default\"] = ApplicationAdapter;\n  });//# sourceURL=exq-admin/adapters/application.js");

;eval("define(\"exq-admin/app\", \n  [\"ember\",\"ember/resolver\",\"ember/load-initializers\",\"exq-admin/config/environment\",\"exports\"],\n  function(__dependency1__, __dependency2__, __dependency3__, __dependency4__, __exports__) {\n    \"use strict\";\n    var Ember = __dependency1__[\"default\"];\n    var Resolver = __dependency2__[\"default\"];\n    var loadInitializers = __dependency3__[\"default\"];\n    var config = __dependency4__[\"default\"];\n\n    Ember.MODEL_FACTORY_INJECTIONS = true;\n\n    var App = Ember.Application.extend({\n      modulePrefix: config.modulePrefix,\n      podModulePrefix: config.podModulePrefix,\n      Resolver: Resolver\n    });\n\n    loadInitializers(App, config.modulePrefix);\n\n    __exports__[\"default\"] = App;\n  });//# sourceURL=exq-admin/app.js");

;eval("define(\"exq-admin/initializers/simple-auth\", \n  [\"simple-auth/configuration\",\"simple-auth/setup\",\"exq-admin/config/environment\",\"exports\"],\n  function(__dependency1__, __dependency2__, __dependency3__, __exports__) {\n    \"use strict\";\n    var Configuration = __dependency1__[\"default\"];\n    var setup = __dependency2__[\"default\"];\n    var ENV = __dependency3__[\"default\"];\n\n    __exports__[\"default\"] = {\n      name:       \'simple-auth\',\n      initialize: function(container, application) {\n        Configuration.load(container, ENV[\'simple-auth\'] || {});\n        setup(container, application);\n      }\n    };\n  });//# sourceURL=exq-admin/initializers/simple-auth.js");

;eval("define(\"exq-admin/models/job\", \n  [\"exports\"],\n  function(__exports__) {\n    \"use strict\";\n    var Job;\n\n    Job = DS.Model.extend({\n      job: DS.attr(\'string\')\n    });\n\n    __exports__[\"default\"] = Job;\n  });//# sourceURL=exq-admin/models/job.js");

;eval("define(\"exq-admin/models/queue\", \n  [\"exports\"],\n  function(__exports__) {\n    \"use strict\";\n    var Queue;\n\n    Queue = DS.Model.extend({\n      size: DS.attr(\'number\'),\n      jobs: DS.hasMany(\'job\')\n    });\n\n    __exports__[\"default\"] = Queue;\n  });//# sourceURL=exq-admin/models/queue.js");

;eval("define(\"exq-admin/router\", \n  [\"ember\",\"exq-admin/config/environment\",\"exports\"],\n  function(__dependency1__, __dependency2__, __exports__) {\n    \"use strict\";\n    var Ember = __dependency1__[\"default\"];\n    var config = __dependency2__[\"default\"];\n    var Router;\n\n    Router = Ember.Router.extend({\n      location: config.locationType\n    });\n\n    Router.map(function() {\n      this.route(\'index\', {\n        path: \'/\'\n      });\n      return this.resource(\'queues\', function() {\n        return this.route(\'show\', {\n          path: \'/:id\'\n        });\n      });\n    });\n\n    __exports__[\"default\"] = Router;\n  });//# sourceURL=exq-admin/router.js");

;eval("define(\"exq-admin/routes/queues/index\", \n  [\"exports\"],\n  function(__exports__) {\n    \"use strict\";\n    var IndexRoute;\n\n    IndexRoute = Ember.Route.extend({\n      model: function(params) {\n        return this.store.find(\'queue\');\n      }\n    });\n\n    __exports__[\"default\"] = IndexRoute;\n  });//# sourceURL=exq-admin/routes/queues/index.js");

;eval("define(\"exq-admin/routes/queues/show\", \n  [\"exports\"],\n  function(__exports__) {\n    \"use strict\";\n    var ShowRoute;\n\n    ShowRoute = Ember.Route.extend({\n      model: function(params) {\n        return this.store.find(\'queue\', params.id);\n      }\n    });\n\n    __exports__[\"default\"] = ShowRoute;\n  });//# sourceURL=exq-admin/routes/queues/show.js");

;eval("define(\"exq-admin/templates/application\", \n  [\"exports\"],\n  function(__exports__) {\n    \"use strict\";\n    __exports__[\"default\"] = Ember.Handlebars.template(function anonymous(Handlebars,depth0,helpers,partials,data) {\n    this.compilerInfo = [4,\'>= 1.0.0\'];\n    helpers = this.merge(helpers, Ember.Handlebars.helpers); data = data || {};\n      var buffer = \'\', stack1;\n\n\n      stack1 = helpers._triageMustache.call(depth0, \"exq-navbar\", {hash:{},hashTypes:{},hashContexts:{},contexts:[depth0],types:[\"ID\"],data:data});\n      if(stack1 || stack1 === 0) { data.buffer.push(stack1); }\n      data.buffer.push(\"<div class=\\\"container-fluid\\\">\");\n      stack1 = helpers._triageMustache.call(depth0, \"outlet\", {hash:{},hashTypes:{},hashContexts:{},contexts:[depth0],types:[\"ID\"],data:data});\n      if(stack1 || stack1 === 0) { data.buffer.push(stack1); }\n      data.buffer.push(\"</div>\");\n      return buffer;\n      \n    });\n  });//# sourceURL=exq-admin/templates/application.js");

;eval("define(\"exq-admin/templates/components/exq-navbar\", \n  [\"exports\"],\n  function(__exports__) {\n    \"use strict\";\n    __exports__[\"default\"] = Ember.Handlebars.template(function anonymous(Handlebars,depth0,helpers,partials,data) {\n    this.compilerInfo = [4,\'>= 1.0.0\'];\n    helpers = this.merge(helpers, Ember.Handlebars.helpers); data = data || {};\n      var buffer = \'\', stack1, helper, options, self=this, helperMissing=helpers.helperMissing;\n\n    function program1(depth0,data) {\n      \n      \n      data.buffer.push(\"Exq\");\n      }\n\n    function program3(depth0,data) {\n      \n      var buffer = \'\';\n      return buffer;\n      }\n\n    function program5(depth0,data) {\n      \n      \n      data.buffer.push(\"Queues\");\n      }\n\n      data.buffer.push(\"<nav role=\\\"navigation\\\" class=\\\"navbar navbar-default\\\"><div class=\\\"container-fluid\\\"><div class=\\\"navbar-header\\\"><button data-target=\\\"#bs-example-navbar-collapse-1\\\" data-toggle=\\\"collapse\\\" type=\\\"button\\\" class=\\\"navbar-toggle collapsed\\\"><span class=\\\"sr-only\\\">Toggle navigation</span><span class=\\\"icon-bar\\\"></span><span class=\\\"icon-bar\\\"></span><span class=\\\"icon-bar\\\"></span></button>\");\n      stack1 = (helper = helpers[\'link-to\'] || (depth0 && depth0[\'link-to\']),options={hash:{\n        \'class\': (\"navbar-brand\")\n      },hashTypes:{\'class\': \"STRING\"},hashContexts:{\'class\': depth0},inverse:self.program(3, program3, data),fn:self.program(1, program1, data),contexts:[depth0],types:[\"STRING\"],data:data},helper ? helper.call(depth0, \"index\", options) : helperMissing.call(depth0, \"link-to\", \"index\", options));\n      if(stack1 || stack1 === 0) { data.buffer.push(stack1); }\n      data.buffer.push(\"</div><div id=\\\"bs-example-navbar-collapse-1\\\" class=\\\"collapse navbar-collapse\\\"><ul class=\\\"nav navbar-nav\\\"><li>\");\n      stack1 = (helper = helpers[\'link-to\'] || (depth0 && depth0[\'link-to\']),options={hash:{},hashTypes:{},hashContexts:{},inverse:self.program(3, program3, data),fn:self.program(5, program5, data),contexts:[depth0],types:[\"STRING\"],data:data},helper ? helper.call(depth0, \"queues.index\", options) : helperMissing.call(depth0, \"link-to\", \"queues.index\", options));\n      if(stack1 || stack1 === 0) { data.buffer.push(stack1); }\n      data.buffer.push(\"</li></ul></div></div></nav>\");\n      return buffer;\n      \n    });\n  });//# sourceURL=exq-admin/templates/components/exq-navbar.js");

;eval("define(\"exq-admin/templates/index\", \n  [\"exports\"],\n  function(__exports__) {\n    \"use strict\";\n    __exports__[\"default\"] = Ember.Handlebars.template(function anonymous(Handlebars,depth0,helpers,partials,data) {\n    this.compilerInfo = [4,\'>= 1.0.0\'];\n    helpers = this.merge(helpers, Ember.Handlebars.helpers); data = data || {};\n      \n\n\n      data.buffer.push(\"<h2>Hello World</h2>\");\n      \n    });\n  });//# sourceURL=exq-admin/templates/index.js");

;eval("define(\"exq-admin/templates/queues/index\", \n  [\"exports\"],\n  function(__exports__) {\n    \"use strict\";\n    __exports__[\"default\"] = Ember.Handlebars.template(function anonymous(Handlebars,depth0,helpers,partials,data) {\n    this.compilerInfo = [4,\'>= 1.0.0\'];\n    helpers = this.merge(helpers, Ember.Handlebars.helpers); data = data || {};\n      var buffer = \'\', stack1, self=this, helperMissing=helpers.helperMissing;\n\n    function program1(depth0,data) {\n      \n      var buffer = \'\', stack1, helper, options;\n      data.buffer.push(\"<li>\");\n      stack1 = (helper = helpers[\'link-to\'] || (depth0 && depth0[\'link-to\']),options={hash:{},hashTypes:{},hashContexts:{},inverse:self.program(4, program4, data),fn:self.program(2, program2, data),contexts:[depth0,depth0],types:[\"STRING\",\"ID\"],data:data},helper ? helper.call(depth0, \"queues.show\", \"queue.id\", options) : helperMissing.call(depth0, \"link-to\", \"queues.show\", \"queue.id\", options));\n      if(stack1 || stack1 === 0) { data.buffer.push(stack1); }\n      data.buffer.push(\" -  \");\n      stack1 = helpers._triageMustache.call(depth0, \"queue.size\", {hash:{},hashTypes:{},hashContexts:{},contexts:[depth0],types:[\"ID\"],data:data});\n      if(stack1 || stack1 === 0) { data.buffer.push(stack1); }\n      data.buffer.push(\"</li>\");\n      return buffer;\n      }\n    function program2(depth0,data) {\n      \n      var stack1;\n      stack1 = helpers._triageMustache.call(depth0, \"queue.id\", {hash:{},hashTypes:{},hashContexts:{},contexts:[depth0],types:[\"ID\"],data:data});\n      if(stack1 || stack1 === 0) { data.buffer.push(stack1); }\n      else { data.buffer.push(\'\'); }\n      }\n\n    function program4(depth0,data) {\n      \n      var buffer = \'\';\n      return buffer;\n      }\n\n      data.buffer.push(\"<h2>Queues</h2><ul>\");\n      stack1 = helpers.each.call(depth0, \"queue\", \"in\", \"model\", {hash:{},hashTypes:{},hashContexts:{},inverse:self.program(4, program4, data),fn:self.program(1, program1, data),contexts:[depth0,depth0,depth0],types:[\"ID\",\"ID\",\"ID\"],data:data});\n      if(stack1 || stack1 === 0) { data.buffer.push(stack1); }\n      data.buffer.push(\"</ul>\");\n      return buffer;\n      \n    });\n  });//# sourceURL=exq-admin/templates/queues/index.js");

;eval("define(\"exq-admin/templates/queues/show\", \n  [\"exports\"],\n  function(__exports__) {\n    \"use strict\";\n    __exports__[\"default\"] = Ember.Handlebars.template(function anonymous(Handlebars,depth0,helpers,partials,data) {\n    this.compilerInfo = [4,\'>= 1.0.0\'];\n    helpers = this.merge(helpers, Ember.Handlebars.helpers); data = data || {};\n      var buffer = \'\', stack1, self=this;\n\n    function program1(depth0,data) {\n      \n      var buffer = \'\', stack1;\n      data.buffer.push(\"<li>\");\n      stack1 = helpers._triageMustache.call(depth0, \"job.id\", {hash:{},hashTypes:{},hashContexts:{},contexts:[depth0],types:[\"ID\"],data:data});\n      if(stack1 || stack1 === 0) { data.buffer.push(stack1); }\n      data.buffer.push(\" -  \");\n      stack1 = helpers._triageMustache.call(depth0, \"job.job\", {hash:{},hashTypes:{},hashContexts:{},contexts:[depth0],types:[\"ID\"],data:data});\n      if(stack1 || stack1 === 0) { data.buffer.push(stack1); }\n      data.buffer.push(\"</li>\");\n      return buffer;\n      }\n\n    function program3(depth0,data) {\n      \n      var buffer = \'\';\n      return buffer;\n      }\n\n      data.buffer.push(\"<h2>Queue:  \");\n      stack1 = helpers._triageMustache.call(depth0, \"model.id\", {hash:{},hashTypes:{},hashContexts:{},contexts:[depth0],types:[\"ID\"],data:data});\n      if(stack1 || stack1 === 0) { data.buffer.push(stack1); }\n      data.buffer.push(\"</h2><ul>\");\n      stack1 = helpers.each.call(depth0, \"job\", \"in\", \"model.jobs\", {hash:{},hashTypes:{},hashContexts:{},inverse:self.program(3, program3, data),fn:self.program(1, program1, data),contexts:[depth0,depth0,depth0],types:[\"ID\",\"ID\",\"ID\"],data:data});\n      if(stack1 || stack1 === 0) { data.buffer.push(stack1); }\n      data.buffer.push(\"</ul>\");\n      return buffer;\n      \n    });\n  });//# sourceURL=exq-admin/templates/queues/show.js");

;eval("define(\"exq-admin/tests/app.jshint\", \n  [],\n  function() {\n    \"use strict\";\n    module(\'JSHint - .\');\n    test(\'app.js should pass jshint\', function() { \n      ok(true, \'app.js should pass jshint.\'); \n    });\n  });//# sourceURL=exq-admin/tests/app.jshint.js");

;eval("define(\"exq-admin/tests/exq-admin/tests/helpers/resolver.jshint\", \n  [],\n  function() {\n    \"use strict\";\n    module(\'JSHint - exq-admin/tests/helpers\');\n    test(\'exq-admin/tests/helpers/resolver.js should pass jshint\', function() { \n      ok(true, \'exq-admin/tests/helpers/resolver.js should pass jshint.\'); \n    });\n  });//# sourceURL=exq-admin/tests/exq-admin/tests/helpers/resolver.jshint.js");

;eval("define(\"exq-admin/tests/exq-admin/tests/helpers/start-app.jshint\", \n  [],\n  function() {\n    \"use strict\";\n    module(\'JSHint - exq-admin/tests/helpers\');\n    test(\'exq-admin/tests/helpers/start-app.js should pass jshint\', function() { \n      ok(true, \'exq-admin/tests/helpers/start-app.js should pass jshint.\'); \n    });\n  });//# sourceURL=exq-admin/tests/exq-admin/tests/helpers/start-app.jshint.js");

;eval("define(\"exq-admin/tests/exq-admin/tests/test-helper.jshint\", \n  [],\n  function() {\n    \"use strict\";\n    module(\'JSHint - exq-admin/tests\');\n    test(\'exq-admin/tests/test-helper.js should pass jshint\', function() { \n      ok(true, \'exq-admin/tests/test-helper.js should pass jshint.\'); \n    });\n  });//# sourceURL=exq-admin/tests/exq-admin/tests/test-helper.jshint.js");

;eval("define(\"exq-admin/tests/helpers/resolver\", \n  [\"ember/resolver\",\"exq-admin/config/environment\",\"exports\"],\n  function(__dependency1__, __dependency2__, __exports__) {\n    \"use strict\";\n    var Resolver = __dependency1__[\"default\"];\n    var config = __dependency2__[\"default\"];\n\n    var resolver = Resolver.create();\n\n    resolver.namespace = {\n      modulePrefix: config.modulePrefix,\n      podModulePrefix: config.podModulePrefix\n    };\n\n    __exports__[\"default\"] = resolver;\n  });//# sourceURL=exq-admin/tests/helpers/resolver.js");

;eval("define(\"exq-admin/tests/helpers/start-app\", \n  [\"ember\",\"exq-admin/app\",\"exq-admin/router\",\"exq-admin/config/environment\",\"exports\"],\n  function(__dependency1__, __dependency2__, __dependency3__, __dependency4__, __exports__) {\n    \"use strict\";\n    var Ember = __dependency1__[\"default\"];\n    var Application = __dependency2__[\"default\"];\n    var Router = __dependency3__[\"default\"];\n    var config = __dependency4__[\"default\"];\n\n    __exports__[\"default\"] = function startApp(attrs) {\n      var App;\n\n      var attributes = Ember.merge({}, config.APP);\n      attributes = Ember.merge(attributes, attrs); // use defaults, but you can override;\n\n      Router.reopen({\n        location: \'none\'\n      });\n\n      Ember.run(function() {\n        App = Application.create(attributes);\n        App.setupForTesting();\n        App.injectTestHelpers();\n      });\n\n      App.reset(); // this shouldn\'t be needed, i want to be able to \"start an app at a specific URL\"\n\n      return App;\n    }\n  });//# sourceURL=exq-admin/tests/helpers/start-app.js");

;eval("define(\"exq-admin/tests/test-helper\", \n  [\"exq-admin/tests/helpers/resolver\",\"ember-qunit\"],\n  function(__dependency1__, __dependency2__) {\n    \"use strict\";\n    var resolver = __dependency1__[\"default\"];\n    var setResolver = __dependency2__.setResolver;\n\n    setResolver(resolver);\n\n    document.write(\'<div id=\"ember-testing-container\"><div id=\"ember-testing\"></div></div>\');\n\n    QUnit.config.urlConfig.push({ id: \'nocontainer\', label: \'Hide container\'});\n    var containerVisibility = QUnit.urlParams.nocontainer ? \'hidden\' : \'visible\';\n    document.getElementById(\'ember-testing-container\').style.visibility = containerVisibility;\n  });//# sourceURL=exq-admin/tests/test-helper.js");

/* jshint ignore:start */

define('exq-admin/config/environment', ['ember'], function(Ember) {
  var metaName = 'exq-admin/config/environment';
  var rawConfig = Ember['default'].$('meta[name="' + metaName + '"]').attr('content');
  var config = JSON.parse(unescape(rawConfig));

  return { 'default': config };
});

if (runningTests) {
  require('exq-admin/tests/test-helper');
} else {
  require('exq-admin/app')['default'].create({"LOG_ACTIVE_GENERATION":true,"LOG_VIEW_LOOKUPS":true});
}

/* jshint ignore:end */
