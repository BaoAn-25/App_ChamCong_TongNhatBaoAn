FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY WebAPI_TongNhatBaoAn.csproj .
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-venv ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY face_worker /opt/face-worker
RUN python3 -m venv /opt/face-env \
    && /opt/face-env/bin/pip install --no-cache-dir -r /opt/face-worker/requirements.txt \
    && /opt/face-env/bin/python /opt/face-worker/download_models.py
ENV PATH="/opt/face-env/bin:${PATH}"
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_ENVIRONMENT=Production
EXPOSE 10000
ENTRYPOINT ["bash", "/opt/face-worker/start.sh"]
