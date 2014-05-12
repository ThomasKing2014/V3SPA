
Base class for "node" objects

    Avispa.Node = Avispa.BaseObject.extend
        el: () -> $SVG('g').attr('class', 'node')

        _init: () ->
            @$circle = $SVG('circle')
                .attr('r', @position.get('radius'))
                .css('fill', @position.get('fill'))
                .appendTo(@$el)

            @$el.attr('id', @options._id)

            @$label = $SVG('text')
                .attr('dy', '0.5em')
                .text(@options.label)
                .appendTo(@$el)

            return

        width: ->
          return @position.get('radius') * 2

        height: ->
          return @position.get('radius') * 2

        render: () ->
            # Calculate our x,y based on offsets
            # and store it
            pos = @AbsPosition()

            @$circle
                .attr('cx', pos.x)
                .attr('cy', pos.y)

            @$label
                .attr('x', pos.x)
                .attr('y', pos.y)

            return @

        OnMouseEnter: (event) ->
            if not Avispa.context.dragItem?
                @$circle.attr('class', 'hover')

                Avispa.context.ide_backend.highlight(@options.data)

            return cancelEvent(event)

        OnMouseLeave: (event) ->
            if not Avispa.context.dragItem?
                @$circle.removeAttr('class')
                Avispa.context.ide_backend.unhighlight()

            return cancelEvent(event)

        LocalBounds: (x, y)->
          ret = 
            x1 : x - @width() / 2
            x2 : x + @width() / 2
            y1 : y - @height() / 2
            y2 : y + @height() / 2


Nodes are circles, and need to offset from the center
of the circle, making calculations different.

        EnforceXOffset: (offset, pwidth)->
            d = @width()
            r = d / 2
            if offset < r
                offset = r
            else if offset + r > pwidth
                offset = pwidth - r

            return offset

        EnforceYOffset: (offset, pheight)->
            d = @height()
            r = d / 2
            if offset < 25 + r
                offset = 25 + r
            else if offset + r > pheight
                offset = pheight - r

            return offset

        Drag: (event) ->
            new_x = (event.clientX / Avispa.context.scale) - @clickOffsetX
            new_y = (event.clientY / Avispa.context.scale) - @clickOffsetY

            new_positions =
              x: new_x
              y: new_y

            @position.set @EnforceBoundingBox(new_positions)

            for child in @children
              do (child)->
                child.ParentDrag()

            return cancelEvent(event)
