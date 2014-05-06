    vespaControllers = angular.module('vespaControllers')

    vespaControllers.controller 'avispaCtrl', ($scope, VespaLogger,
        IDEBackend, $timeout) ->

      $scope.domain_data = null
      $scope.objects ?= 
          ports: {}
          domains: {}
          connections: {}
      $scope.parent ?= [null]

      $scope.avispa = new Avispa
        el: $('#surface svg')

      $('#surface').append $scope.avispa.$el

Manage the position of items within this view.

Clean up the Avispa view

      cleanup = ->
          $scope.objects =
              ports: {}
              domains: {}
              connections: {}
          $scope.parent = [null]

          $('#surface svg .objects')[0].innerHTML = ''
          $('#surface svg .links')[0].innerHTML = ''
          $('#surface svg .labels')[0].innerHTML = ''
          $('#surface svg .groups')[0].innerHTML = ''


A general update function for the Avispa view. This only refreshes
when the domain data has actually changed to prevent flickering.

      update_view = (data)->
        if _.size(data.errors) > 0
            $scope.policy_data = null
            cleanup()

        else
          if not _.isEqual(data.result, $scope.policy_data)
            $scope.policy_data = data.result

            cleanup()
            $scope.avispa = new Avispa
              el: $('#surface svg')

            $scope.parseDomain(data.result.domains[data.result.root])

Force a redraw on all the children

            for id of data.result.domains[data.result.root].subdomains
              do (id)->
                _.each $scope.objects.domains[id].children, (child)->
                  child.ParentDrag()

            $scope.parseConns(data.result.connections)


      IDEBackend.add_hook "json_changed", update_view
      $scope.$on "$destroy", ->
        IDEBackend.unhook "json_changed", update_view

The following is more or less mapped from the backbone style code.
ID's MUST be fully qualified, or Avispa renders horribly wrong.

      fqid = (id, parent)->
        if parent?
          return "#{parent.options._id}.#{id}"
        else
          return id

      $scope.createDomain = (id, parents, obj, coords) ->
          domain = new Domain
              _id: if obj?.path then obj.path else id
              parent: parents[0]
              name: if obj?.name then obj.name else "[#{id}]"
              position: coords
              data: if obj? then obj else null
              klasses: ['filtered'] unless obj?

          $scope.objects.domains[id] = domain

          if obj
            IDEBackend.add_selection_range_object 'dsl', obj.srcloc.start.line, domain

          $scope.avispa.$groups.append domain.$el

      $scope.createPort = (id, parents, obj, coords) ->
          port = new Port
              _id: obj.path
              parent: parents[0]
              label: obj.name
              position: coords
              data: obj

          $scope.objects.ports[id] = port

          IDEBackend.add_selection_range_object 'dsl', obj.srcloc.start.line, port
          $scope.avispa.$objects.append port.$el

          return port

      $scope.createLink = (dir, left, right, data) ->
          link = new Avispa.Link
              direction: dir
              left: left
              right: right
              data: data

          IDEBackend.add_selection_range_object 'dsl', data.srcloc.start.line, link
          $scope.avispa.$links.append link.$el

      $scope.parseDomain = (domain) ->
          domain_pos = 
            x: 10
            y: 100
            w: 200
            h: 200
          port_pos = x: 40, y: 40
          port_layout_store = []


          for id, subdomain of domain.subdomains
            do (id, subdomain)->
              if id not of $scope.policy_data.domains
                coords =
                    offset_x: domain_pos.x + 10
                    offset_y: 100 + 10
                    w: 50
                    h: 50
                $scope.createDomain id, $scope.parent, subdomain, coords

              else

                subdomain = $scope.policy_data.domains[id]
                subdomain_count = _.size subdomain.subdomains
                size = Math.ceil(Math.sqrt(subdomain_count)) + 1
                coords =
                    offset_x: domain_pos.x
                    offset_y: domain_pos.y
                    w: (domain_pos.w * 1.1) * size || domain_pos.w
                    h: (domain_pos.h * 1.1) * size || domain_pos.h

                $scope.createDomain id, $scope.parent, subdomain, coords

                # Set the width and height directly - it changes based on the 
                # number of subnodes, and otherwise it will be cached
                $scope.objects.domains[id].position.set
                    w: (domain_pos.w * 1.1) * size || domain_pos.w
                    h: (domain_pos.h * 1.1) * size || domain_pos.h

                $scope.parent.unshift $scope.objects.domains[id]
                $scope.parseDomain(subdomain)
                $scope.parent.shift()

              domain_pos.x += 210

          for id, idx in domain.ports
            do (id)->
              port_layout_store.push 
                  index: idx
                  x: 0
                  y: 0
                  px: 0
                  py: 0
                  id: id

          port_force = d3.layout.force().nodes(port_layout_store)
                      .size([domain_pos.w, domain_pos.h])
                      .gravity(0.05)
                      .charge(-100)
                      .chargeDistance(domain_pos.w)
                      .on('tick', ->
                        for port in port_layout_store
                          if port.x > domain_pos.w
                            port.x = domain_pos.w
                          else if port.x < 0
                            port.x = 0
                          if port.y > domain_pos.h
                            port.y = domain_pos.h
                          else if port.y < 0
                            port.y = 0
                      )

          port_force.start()
          for x in [1..200]
            port_force.tick()
          port_force.stop()

          for port_layout in port_layout_store
              port = $scope.policy_data.ports[port_layout.id]
              coords =
                  offset_x: port_layout.x
                  offset_y: port_layout.y
                  radius: 30
                  fill: '#eeeeec'


              $scope.createPort port_layout.id,  $scope.parent, port, coords


      $scope.parseConns = (connections)->

          for connection in connections
              $scope.createLink connection.connection,
                                $scope.objects.ports[connection.left],
                                $scope.objects.ports[connection.right],
                                connection

Actually load the thing the first time.

      start_data = IDEBackend.get_json()
      if start_data
          update_view(start_data)

Lobster-specific definitions for Avispa

    class GenericModel
      constructor: (vals, identifier)->
        @observers = {}

If we have an identifier, then instantiate a PositionManager
and use it's data variable as the data variable. Otherwise just
store it locally.

        if identifier?
We are outside of Angular, so we need to retrieve the services
from the injector

          injector = angular.element('body').injector()
          PositionManager = injector.get('PositionManager')
          IDEBackend = injector.get('IDEBackend')

          @posMgr = PositionManager(
            "avispa.#{identifier}::#{IDEBackend.current_policy._id}",
            vals,
            ['x', 'y', 'w', 'h']
          )
          @data = @posMgr.data

          @posMgr.on_change =>
            @notify ['change']

        else
          @data = vals

      bind: (event, func, _this)->
        @observers[event] ?= []
        @observers[event].push([ _this, func ])

      notify: (event)->
        for observer in @observers[event]
          do (observer)=>
            observer[1].apply observer[0], [@]

      get: (key)->
        return @data[key]

      set: (obj)->
        @_set(obj)

      _set: (obj)->
        changed = false
        if @posMgr?
          changed = @posMgr.update(obj)
        else
          for k, v of obj
            do (k, v)->
              if @data[k] != v
                @data[k] = v
                changed = true

          # This is intentionally inside the else block.
          # posMgr notifies any of its changes
          if changed
            @notify(['change'])

    Port = Avispa.Node

    Domain = Avispa.Group.extend

        init: () ->

            @$label = $SVG('text')
                .attr('dx', '0.5em')
                .attr('dy', '1.5em')
                .text(@options.name or @options.id)
                .appendTo(@$el)

            return @

        render: () ->
            pos = @AbsPosition()
            @$rect
                .attr('x', pos.x)
                .attr('y', pos.y)
                .attr('width',  @position.get('w'))
                .attr('height', @position.get('h'))
            @$label
                .attr('x', pos.x)
                .attr('y', pos.y)
            return @

