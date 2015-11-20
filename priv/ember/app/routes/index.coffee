IndexRoute = Ember.Route.extend
  timeout: null
  setupController: (controller, model) ->
    @_super(controller, model)
    self = this
    updater = window.setInterval(->
      self.store.findAll('realtime').then((data) ->
        controller.set('dashboard_data', data)
        controller.set('date', new Date())
      )
    , 2000)
    @set('timeout', updater)

  deactivate: ->
    clearInterval(@get('timeout'))
    @set('timeout', null)

`export default IndexRoute`
