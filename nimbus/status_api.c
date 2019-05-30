#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <unistd.h>
#include <time.h>

typedef struct {
  uint8_t* decoded;
  size_t decodedLen;
  uint32_t timestamp;
  uint32_t ttl;
  uint8_t topic[4];
  double pow;
  uint8_t hash[32];
} received_nessage;


void NimMain();

void nimbus_start(uint16_t port);
void nimbus_poll();
void nimbus_post(const char* payload);

typedef void (*received_msg_handler)(received_nessage* msg);

void nimbus_subscribe(const char* channel, received_msg_handler msg);

void print_msg(received_nessage* msg) {
  printf("Got message! %ld\n", msg->decodedLen);
}

int main(int argc, char* argv[]) {
  time_t lastmsg;

  NimMain();
  nimbus_start(30303);

  nimbus_subscribe("status-test-c", print_msg);

  lastmsg = time(NULL);

  while(1) {
    usleep(1);

    if (lastmsg + 1 <= time(NULL)) {
      lastmsg = time(NULL);
      printf("Posting hello\n");
      nimbus_post("hello");
    }
    nimbus_poll();
  }
}
