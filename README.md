# axon

A **presence shader** for [Alfred](https://github.com/tylerreckart/alfred) and [Arbiter](https://github.com/tylerreckart/arbiter).

```
mic / PTT ──► listen ──► STT ──► think (Arbiter SSE) ──► speak (TTS PCM) ──► idle
                                    │
                              tool_call raises chaos
```

## Modes

| Mode | State |
|------|-------|
| `idle` | waiting |
| `listen` | mic open / PTT |
| `think` | STT + Arbiter run |
| `speak` | TTS chunks |

The shader never talks to the network. Hosts map Alfred’s turn pipeline and
Arbiter’s SSE catalog onto the [presence protocol](docs/protocol.md).

## Quick start

```sh
python3 -m http.server 4173
# open http://127.0.0.1:4173/web/
```

## License

Apache-2.0
