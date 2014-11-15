/*globals ENV QUnit EmberDev */

(function() {
  window.Ember = {
    testing: true
  };
  window.ENV = window.ENV || {};

  // Test for "hooks in ENV.EMBER_LOAD_HOOKS['hookName'] get executed"
  ENV.EMBER_LOAD_HOOKS = ENV.EMBER_LOAD_HOOKS || {};
  ENV.EMBER_LOAD_HOOKS.__before_ember_test_hook__ = ENV.EMBER_LOAD_HOOKS.__before_ember_test_hook__ || [];
  ENV.__test_hook_count__ = 0;
  ENV.EMBER_LOAD_HOOKS.__before_ember_test_hook__.push(function(object) {
    ENV.__test_hook_count__ += object;
  });

  window.ENV.FEATURES = !!QUnit.urlParams.prod ? {"ember-routing-named-substates":null,"ember-routing-add-model-option":true,"ember-routing-linkto-target-attribute":true,"ember-routing-will-change-hooks":null,"ember-routing-multi-current-when":true,"ember-routing-auto-location-uses-replace-state-for-history":true,"event-dispatcher-can-disable-event-manager":null,"ember-metal-is-present":true,"property-brace-expansion-improvement":true,"ember-routing-handlebars-action-with-key-code":null,"ember-runtime-item-controller-inline-class":null,"ember-metal-injected-properties":null,"mandatory-setter":false} : {"ember-routing-named-substates":null,"ember-routing-add-model-option":true,"ember-routing-linkto-target-attribute":true,"ember-routing-will-change-hooks":null,"ember-routing-multi-current-when":true,"ember-routing-auto-location-uses-replace-state-for-history":true,"event-dispatcher-can-disable-event-manager":null,"ember-metal-is-present":true,"property-brace-expansion-improvement":true,"ember-routing-handlebars-action-with-key-code":null,"ember-runtime-item-controller-inline-class":null,"ember-metal-injected-properties":null,"mandatory-setter":true};

  // Handle extending prototypes
  ENV['EXTEND_PROTOTYPES'] = !!QUnit.urlParams.extendprototypes;

  // Handle testing feature flags
  ENV['ENABLE_OPTIONAL_FEATURES'] = !!QUnit.urlParams.enableoptionalfeatures;

  // Don't worry about jQuery version
  ENV['FORCE_JQUERY'] = true;

  // Don't worry about jQuery version
  ENV['RAISE_ON_DEPRECATION'] = !!QUnit.urlParams.raiseonunhandleddeprecation;

  if (EmberDev.jsHint) {
    // jsHint makes its own Object.create stub, we don't want to use this
    ENV['STUB_OBJECT_CREATE'] = !Object.create;
  }
})();
