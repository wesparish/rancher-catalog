Need to deploy with a post-renderer

```Bash
helm -n ollama \
    upgrade \
    --install \
    ollama-wes . \
    --post-renderer ./post-renderer.sh
```