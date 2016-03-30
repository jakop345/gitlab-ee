class @MirrorUrlProtector
  constructor: ->
    $('.toggle-remote-credentials').on 'click', (e) =>
      e.preventDefault()

      anchor = $(e.target)
      inputUrl = anchor.prev()

      switch anchor.text()
        when 'Show credentials'
          anchor.text('Hide credentials')
          inputUrl.val(inputUrl.data('full-url'))
        when 'Hide credentials'
          anchor.text('Show credentials')
          inputUrl.val(inputUrl.data('safe-url'))
