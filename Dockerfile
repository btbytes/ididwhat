FROM nimlang/nim:latest

WORKDIR /app

COPY . .

RUN nimble install -y
RUN nimble build

CMD ["./main"]
