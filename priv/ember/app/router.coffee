`import Ember from 'ember'`
`import config from './config/environment'`

Router = Ember.Router.extend
  location: config.locationType


Router.map ->
  @route 'index', {path: '/'}
  @route 'queues', {resetNamespace: true }, ->
    @route 'show', {path: '/:id'}
  @route 'processes', {resetNamespace: true }, ->
    @route 'index', {path: '/'}
  @route 'retries', {resetNamespace: true }, ->
    @route 'index', {path: '/'}
  @route 'failures', {resetNamespace: true }, ->
    @route 'index', {path: '/'}
`export default Router`
