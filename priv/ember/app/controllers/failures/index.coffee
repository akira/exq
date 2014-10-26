IndexController = Ember.Controller.extend
  
  actions:
    clearFailures: ->
      self = this
      jQuery.ajax({url: "#{window.exqNamespace}api/failures", type: "DELETE"}).done(->
        self.store.all('failure').forEach((f) ->
          f.deleteRecord()
        )
        self.send('reloadStats')
      )
    removeFailure: (failure) ->
      self = this
      failure.deleteRecord()
      failure.save().then((f) ->
        self.send('reloadStats')
      )
      
      

`export default IndexController`