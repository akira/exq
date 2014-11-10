`import Ember from 'ember'`
`import config from './config/environment'`

Router = Ember.Router.extend
  location: config.locationType


Router.map ->
  @route 'index', {path: '/'}
  @resource 'queues', ->
    @route 'show', {path: '/:id'}
  @resource 'processes', ->
    @route 'index', {path: '/'}
  @resource 'failures', ->
    @route 'index', {path: '/'}
`export default Router`
