`import request from 'ic-ajax'`

IndexController = Ember.Controller.extend

  actions:
    clearFailures: ->
      self = this
      # jQuery.ajax({url: "#{window.exqNamespace}api/failures", type: "DELETE"}).done(->
      request({url: "api/failures", type: "DELETE"}).then ->
        console.log("clearFailures request finished")
        self.store.findAll('failure').forEach((f) ->
          f.deleteRecord()
        )
        self.send('reloadStats')
    retryFailure: (failure) ->
    removeFailure: (failure) ->
      self = this
      failure.deleteRecord()
      failure.save().then((f) ->
        self.send('reloadStats')
      )



`export default IndexController`
