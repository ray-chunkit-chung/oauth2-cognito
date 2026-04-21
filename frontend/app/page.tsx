"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import Image from "next/image";
import { useAuth, signOut } from "@/hooks/use-auth";
import {
  ChatMessage,
  ChatSession,
  getChatSession,
  listChatSessions,
  postChatMessage,
} from "@/lib/chat-api";

function formatTimestamp(value: string): string {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "";
  }

  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  }).format(date);
}

function toErrorMessage(error: unknown): string {
  if (error instanceof Error && error.message) {
    return error.message;
  }
  return "Something went wrong while contacting the chat API.";
}

export default function Home() {
  const router = useRouter();
  const { user, isAuthenticated, isLoading } = useAuth();
  const [sessions, setSessions] = useState<ChatSession[]>([]);
  const [activeSessionId, setActiveSessionId] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [isLoadingSessions, setIsLoadingSessions] = useState(false);
  const [isLoadingMessages, setIsLoadingMessages] = useState(false);
  const [isSending, setIsSending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const isChatConfigured = Boolean(
    (process.env.NEXT_PUBLIC_CHAT_API_BASE_URL ?? "").trim(),
  );

  const orderedSessions = useMemo(
    () =>
      [...sessions].sort((a, b) => {
        if (a.updatedAt === b.updatedAt) {
          return 0;
        }
        return a.updatedAt > b.updatedAt ? -1 : 1;
      }),
    [sessions],
  );

  useEffect(() => {
    if (!isLoading && !isAuthenticated) {
      router.replace("/login");
    }
  }, [isAuthenticated, isLoading, router]);

  useEffect(() => {
    if (isLoading || !isAuthenticated || !isChatConfigured) {
      return;
    }

    let cancelled = false;

    async function loadSessions() {
      setIsLoadingSessions(true);
      setError(null);

      try {
        const response = await listChatSessions();
        if (cancelled) {
          return;
        }

        setSessions(response.sessions);
        setActiveSessionId((prev) => {
          if (
            prev &&
            response.sessions.some((session) => session.id === prev)
          ) {
            return prev;
          }

          if (response.sessions.length > 0) {
            return response.sessions[0].id;
          }

          return null;
        });
      } catch (loadError) {
        if (!cancelled) {
          setError(toErrorMessage(loadError));
        }
      } finally {
        if (!cancelled) {
          setIsLoadingSessions(false);
        }
      }
    }

    void loadSessions();

    return () => {
      cancelled = true;
    };
  }, [isAuthenticated, isChatConfigured, isLoading]);

  useEffect(() => {
    if (
      isLoading ||
      !isAuthenticated ||
      !isChatConfigured ||
      !activeSessionId
    ) {
      return;
    }

    const sessionId = activeSessionId;

    let cancelled = false;

    async function loadMessages() {
      setIsLoadingMessages(true);
      setError(null);

      try {
        const response = await getChatSession(sessionId);
        if (cancelled) {
          return;
        }

        setMessages(response.messages);
      } catch (loadError) {
        if (!cancelled) {
          setError(toErrorMessage(loadError));
        }
      } finally {
        if (!cancelled) {
          setIsLoadingMessages(false);
        }
      }
    }

    void loadMessages();

    return () => {
      cancelled = true;
    };
  }, [activeSessionId, isAuthenticated, isChatConfigured, isLoading]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();

    const text = draft.trim();
    if (!text || isSending || !isChatConfigured) {
      return;
    }

    const optimisticUserMessage: ChatMessage = {
      id: `temp-${Date.now()}`,
      role: "user",
      content: text,
      createdAt: new Date().toISOString(),
    };

    setDraft("");
    setError(null);
    setIsSending(true);
    setMessages((prev) => [...prev, optimisticUserMessage]);

    try {
      const response = await postChatMessage({
        message: text,
        sessionId: activeSessionId ?? undefined,
      });

      setActiveSessionId(response.session.id);
      setMessages((prev) => [
        ...prev.filter((item) => item.id !== optimisticUserMessage.id),
        response.userMessage,
        response.assistantMessage,
      ]);
      setSessions((prev) => {
        const withoutCurrent = prev.filter(
          (session) => session.id !== response.session.id,
        );
        return [response.session, ...withoutCurrent];
      });
    } catch (sendError) {
      setMessages((prev) =>
        prev.filter((item) => item.id !== optimisticUserMessage.id),
      );
      setDraft(text);
      setError(toErrorMessage(sendError));
    } finally {
      setIsSending(false);
    }
  }

  function startNewChat() {
    setActiveSessionId(null);
    setMessages([]);
    setError(null);
  }

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-900 px-6 text-slate-100">
        <p className="text-sm text-slate-300">Loading...</p>
      </div>
    );
  }

  if (!isAuthenticated) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-900 px-6 text-slate-100">
        <p className="text-sm text-slate-300">Redirecting to login...</p>
      </div>
    );
  }

  if (!isChatConfigured) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-slate-900 px-6 text-slate-100">
        <div className="w-full max-w-lg rounded-2xl border border-amber-400/40 bg-slate-950/80 p-7 shadow-lg shadow-black/30">
          <h1 className="text-xl font-semibold text-amber-300">
            Chat API is not configured
          </h1>
          <p className="mt-3 text-sm text-slate-300">
            Set NEXT_PUBLIC_CHAT_API_BASE_URL in frontend environment settings.
          </p>
          <button
            type="button"
            onClick={() => signOut()}
            className="mt-6 inline-flex h-10 items-center justify-center rounded-lg border border-slate-600 bg-slate-800 px-4 text-sm font-medium text-slate-100 transition-colors hover:bg-slate-700"
          >
            Sign out
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gradient-to-b from-slate-900 via-slate-950 to-slate-900 text-slate-100">
      <main className="mx-auto flex min-h-screen w-full max-w-7xl flex-col px-4 py-4 sm:px-6 lg:px-8">
        <div className="grid min-h-[calc(100vh-2rem)] grid-cols-1 gap-4 lg:grid-cols-[300px_1fr]">
          <aside className="flex flex-col rounded-2xl border border-slate-800 bg-slate-950/80 p-4 shadow-xl shadow-black/20">
            <div className="mb-4 flex items-center justify-between gap-2">
              <h1 className="text-base font-semibold tracking-wide text-slate-200">
                Chats
              </h1>
              <button
                type="button"
                onClick={startNewChat}
                className="h-9 rounded-lg border border-slate-700 bg-slate-800 px-3 text-xs font-semibold uppercase tracking-wide text-slate-100 transition-colors hover:bg-slate-700"
              >
                New
              </button>
            </div>

            <div className="space-y-2 overflow-y-auto pr-1">
              {isLoadingSessions && (
                <p className="px-2 text-xs text-slate-400">
                  Loading sessions...
                </p>
              )}

              {!isLoadingSessions && orderedSessions.length === 0 && (
                <p className="px-2 text-xs text-slate-400">
                  No chat history yet. Start a new conversation.
                </p>
              )}

              {orderedSessions.map((session) => (
                <button
                  key={session.id}
                  type="button"
                  onClick={() => setActiveSessionId(session.id)}
                  className={`w-full rounded-xl border p-3 text-left transition-colors ${
                    session.id === activeSessionId
                      ? "border-cyan-500/60 bg-cyan-500/15"
                      : "border-slate-800 bg-slate-900/60 hover:border-slate-700 hover:bg-slate-900"
                  }`}
                >
                  <p className="line-clamp-2 text-sm font-medium text-slate-100">
                    {session.title}
                  </p>
                  <p className="mt-1 line-clamp-1 text-xs text-slate-400">
                    {session.lastMessagePreview || "No assistant reply yet"}
                  </p>
                </button>
              ))}
            </div>
          </aside>

          <section className="flex min-h-0 flex-col rounded-2xl border border-slate-800 bg-slate-950/80 shadow-xl shadow-black/20">
            <header className="flex items-center justify-between border-b border-slate-800 px-5 py-4">
              <div className="flex min-w-0 items-center gap-3">
                {user?.image && (
                  <Image
                    src={user.image}
                    alt="Avatar"
                    width={36}
                    height={36}
                    className="rounded-full"
                  />
                )}
                <div className="min-w-0">
                  <p className="truncate text-sm font-semibold text-slate-100">
                    {user?.name || "Authenticated user"}
                  </p>
                  <p className="truncate text-xs text-slate-400">
                    {user?.email}
                  </p>
                </div>
              </div>

              <button
                type="button"
                onClick={() => signOut()}
                className="h-9 rounded-lg border border-slate-700 bg-slate-900 px-3 text-sm font-medium text-slate-100 transition-colors hover:bg-slate-800"
              >
                Sign out
              </button>
            </header>

            <div className="flex-1 space-y-4 overflow-y-auto px-5 py-5">
              {isLoadingMessages && (
                <p className="text-sm text-slate-400">Loading messages...</p>
              )}

              {!isLoadingMessages && messages.length === 0 && (
                <div className="rounded-xl border border-slate-800 bg-slate-900/60 p-4 text-sm text-slate-300">
                  Ask anything to start your first message in this chat.
                </div>
              )}

              {messages.map((message) => {
                const isUser = message.role === "user";
                return (
                  <article
                    key={message.id}
                    className={`max-w-[85%] rounded-2xl px-4 py-3 text-sm shadow ${
                      isUser
                        ? "ml-auto bg-cyan-500 text-slate-950"
                        : "mr-auto border border-slate-700 bg-slate-900 text-slate-100"
                    }`}
                  >
                    <p className="whitespace-pre-wrap leading-relaxed">
                      {message.content}
                    </p>
                    <p
                      className={`mt-2 text-[11px] ${
                        isUser ? "text-cyan-950/80" : "text-slate-400"
                      }`}
                    >
                      {formatTimestamp(message.createdAt)}
                    </p>
                  </article>
                );
              })}
            </div>

            {error && (
              <div className="mx-5 mb-3 rounded-lg border border-rose-500/40 bg-rose-900/20 px-3 py-2 text-sm text-rose-200">
                {error}
              </div>
            )}

            <form
              onSubmit={handleSubmit}
              className="border-t border-slate-800 px-4 py-4 sm:px-5"
            >
              <div className="flex items-end gap-3">
                <textarea
                  value={draft}
                  onChange={(event) => setDraft(event.target.value)}
                  placeholder="Type your question"
                  rows={2}
                  className="min-h-[52px] flex-1 resize-y rounded-xl border border-slate-700 bg-slate-900 px-3 py-2 text-sm text-slate-100 outline-none ring-cyan-400 placeholder:text-slate-500 focus:ring"
                  disabled={isSending}
                />

                <button
                  type="submit"
                  disabled={isSending || !draft.trim()}
                  className="h-11 rounded-xl bg-cyan-400 px-4 text-sm font-semibold text-slate-950 transition-colors hover:bg-cyan-300 disabled:cursor-not-allowed disabled:bg-slate-700 disabled:text-slate-300"
                >
                  {isSending ? "Sending..." : "Send"}
                </button>
              </div>
            </form>
          </section>
        </div>
      </main>
    </div>
  );
}
