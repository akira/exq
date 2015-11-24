IndexController = Ember.Controller.extend

  actions:
    clearProcesses: ->
      self = this
      jQuery.ajax({url: "#{window.exqNamespace}api/processes", type: "DELETE"}).done(->
        self.store.findAll('process').forEach((p) ->
          p.deleteRecord()
          self.send('reloadStats')
        )
      )


`export default IndexController`
