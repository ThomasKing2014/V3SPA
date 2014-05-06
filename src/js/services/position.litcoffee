    services = angular.module 'vespa.services'

    services.factory 'PositionManager', (SockJSService, $q, $cacheFactory)->

      class PositionMgr
        constructor: (@id, defaults = {}, @local = {})->

          @percolate = _.throttle @_percolate, 1000, leading: false

          @data = defaults

          @loading = true
          @retrieve().then =>
            @loading = false

          @notifier = null

        update: (data)=>
          changed = false
          @data ?= {}
          for k, v of data
            if @data[k] != v
              @data[k] = v
              changed = true
              if not _.contains @local, k # if it's a local only, don't mark changed.
                nonlocal_changed = true

          if changed
            if nonlocal_changed and not @loading
              @percolate()

            @notifier()
          return changed

Register a notifier for when the underlying data changes.

        on_change: (callback)->
          @notifier = callback

Percolate changes to the server

        _percolate: =>

          d = $q.defer()

          updates = _.omit @data, @local
          updates.id = @id
          updates._id = @data._id

          req = 
            domain: 'location'
            request: 'update'
            payload: updates

          SockJSService.send req, (result)=>
            if result.error 
              d.reject result.payload
            else
              d.resolve result.payload

          return d.promise


        retrieve: ()=>
          d = $q.defer()

          req = 
            domain: 'location'
            request: 'get'
            payload: 
              id: @id


          SockJSService.send req, (result)=>
            if result.error 
              d.reject result.payload
            else
              console.log "#{@id} retrieved position from server"
              if result.payload? and not _.isEmpty(result.payload)
                # The server updated the location. Update the data
                # and notify anyone who might care.
                _.extend @data, result.payload
                @notifier()
              else
                # the defaults were better, send them to the server
                # use _percolate because we want to send immediately
                # and get the object id back so we can reference it properly.
                percolated = @_percolate()
                percolated.then (data)=>
                  _.extend @data, data
              d.resolve result.payload

          return d.promise


When the factory function is called, actually return an object that
can be used to retrieve positions. Retrieve a cached manager if possible.

      cache = $cacheFactory('position_managers', {capacity: 50})

      return (id, defaults, locals)->
        manager = cache.get(id)
        if not manager?
          manager = new PositionMgr(id, defaults, locals)
          cache.put(id, manager)
        return manager
