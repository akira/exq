IndexController = Ember.Controller.extend
  date: null,
  chartOptions: {
    bezierCurve : false,
    animation: false,
    scaleShowLabels: true,
    showTooltips: true,
    responsive: true,
    pointDot : false,
    pointHitDetectionRadius : 2
  }

  dashboard_data: {}
  graph_dashboard_data: (->
    if @get('date') != null
      # Get the last 120 seconds
      d = moment.utc(@get('date'))
      labels = []
      mydates = []
      for t in [0...60]
        labels.push("")
        mydates.push(moment.utc(d.valueOf() - (t*1000)))


      rtdata = @store.findAll('realtime')

      success_set = []
      failure_set = []

      for dt in mydates
        key = dt.format("YYYY-MM-DD HH:mm:ss ZZ")
        successes = rtdata.filterBy("id", "s#{key}")
        failures = rtdata.filterBy("id", "f#{key}")
        s = 0
        s = successes[0].get('count') if successes.length > 0
        f = 0
        f = failures[0].get('count') if failures.length > 0
        success_set.push(s)
        failure_set.push(f)

      {
        labels: labels,
        datasets: [
          {
            label: "Failures",
            fillColor: "rgba(255,255,255,0)",
            strokeColor: "rgba(151,187,205,1)",
            pointColor: "rgba(151,187,205,1)",
            pointStrokeColor: "#fff",
            pointHighlightFill: "#fff",
            pointHighlightStroke: "rgba(151,187,205,1)",
            data: success_set.reverse()
          },
          {
            label: "Sucesses",
            fillColor: "rgba(255,255,255,0)",
            strokeColor: "rgba(238,77,77,1)",
            pointColor: "rgba(238,77,77,1)",
            pointStrokeColor: "#fff",
            pointHighlightFill: "#fff",
            pointHighlightStroke: "rgba(238,77,77,1)",
            data: failure_set.reverse()
          }
        ]
      }
    else
      {labels: [], datasets: [data:[]]}
  ).property('dashboard_data', 'date')

`export default IndexController`
