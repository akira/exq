IndexController = Ember.Controller.extend

  actions:
    clearAll: ->
      alert('clearAll')
    deleteQueue: (queue) ->
      if confirm("Are you sure you want to delete #{queue.id} and all its jobs?")
        self = this
        queue.deleteRecord()
        queue.save().then (q) ->
          self.send('reloadStats')


`export default IndexController`
