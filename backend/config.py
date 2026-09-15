from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    anthropic_api_key: str = ""
    model_name: str = "claude-sonnet-4-20250514"
    embedding_model: str = "all-MiniLM-L6-v2"
    chroma_persist_dir: str = "./data/chroma"
    max_memory_results: int = 5
    max_conversation_history: int = 20

    model_config = {"env_file": ".env"}


settings = Settings()
