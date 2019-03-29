<div class="copyright" >
  {% set current = date(Date.now(), "YYYY") %}
  &copy; {% if theme.since and theme.since != current %} {{ theme.since }} - {% endif %}
  <span itemprop="copyrightYear">{{ current }}</span>
  <span class="with-love">
    <i class="fa fa-{{ theme.authoricon }}"></i>
  </span>
  <span class="author" itemprop="copyrightHolder">{{ config.author }}</span>
</div>

{% if theme.copyright %}
<div class="powered-by">
  {{ __('footer.powered', '<a class="theme-link" href="https://hexo.io">Hexo</a>') }}
</div>

<div class="theme-info">
  {{ __('footer.theme') }} -
  <a class="theme-link" href="https://github.com/iissnan/hexo-theme-next">
    NexT.{{ theme.scheme }}
  </a>
</div>
{% endif %}

{% if page.mermaid %}
        <script type="text/javascript" src="https://cdnjs.cloudflare.com/ajax/libs/mermaid/7.1.0/mermaid.min.js"></script>
        <script>
            var config = {
                startOnLoad:true,
                flowchart:{
                    useMaxWidth:false,
                    htmlLabels:true
                }
            };
            mermaid.initialize(config);
            $(function(){
                var elements = document.getElementsByClassName("language-mermaid");
                for (var i = elements.length; i--;) {
                    element = elements[i];
                    var graphDefinition = element.innerText;
                    if (graphDefinition) {
                        var svg = mermaid.render('ha_mermaid_' + i, graphDefinition, function(svg){});
                        if (svg) {
                            var svgElement = document.createElement('div');
                            preNode = element.parentNode;
                            svgElement.innerHTML = svg;
                            svgElement.setAttribute('class', 'mermaid');
                            svgElement.setAttribute('data-processed', 'true');
                            preNode.parentNode.replaceChild(svgElement, preNode);
                        }
                    }
                }
            });
        </script>
{% endif %}
