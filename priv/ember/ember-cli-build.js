/* global require, module */

var EmberApp = require('ember-cli/lib/broccoli/ember-app');

module.exports = function(defaults) {
  var app = new EmberApp(defaults, {
    sassOptions: {
      includePaths: [
        'bower_components/bootstrap-sass-official/assets/stylesheets',
        'bower_components/bootswatch-scss'
      ]
    }
  });

  app.import("bower_components/moment/moment.js");

  return app.toTree();
};
