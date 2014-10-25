/* global require, module */

var EmberApp = require('ember-cli/lib/broccoli/ember-app');

var app = new EmberApp({
  sassOptions: {
    includePaths: [
      'bower_components/bootstrap-sass-official/assets/stylesheets',
      'bower_components/bootswatch-scss'
    ]
  }});
module.exports = app.toTree();
